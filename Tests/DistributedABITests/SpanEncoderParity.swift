@testable import DistributedABI
import Testing

//  SpanEncoder writes the SAME wire format as BufferEncoder, straight into a caller-reserved
//  region (no [UInt8] staging, no send copy). These tests pin that parity: for each wire-format
//  primitive, the bytes SpanEncoder writes into a reserved buffer must equal the bytes
//  BufferEncoder produces, and must decode back through BufferDecoder.
//
//  NOTE: `SpanEncoder` is `~Copyable`/`~Escapable`. A `~Copyable` value cannot be mutated
//  through a captured closure, so each test constructs and drives the encoder at top-level
//  scope (no nested `withUTF8`/`withUnsafeBytes` closure around the encoder mutations); the
//  bytes to bulk-copy are materialized into a local `[UInt8]` first.

@Suite struct SpanEncoderParity {
    @Test static func littleEndianIntegers() {
        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 64, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var s: SpanEncoder = .init(raw)
        s.appendLittleEndian(UInt64(0x0102_0304_0506_0708))
        s.appendLittleEndian(UInt32(0xAABB_CCDD))
        s.appendLittleEndian(Int64(-1))
        s.appendLittleEndian(UInt16(0x1234))
        s.append(UInt8(0x42))
        let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))

        var encoder: BufferEncoder = .init(capacity: 64)
        UInt64(0x0102_0304_0506_0708).encode(to: &encoder)
        UInt32(0xAABB_CCDD).encode(to: &encoder)
        Int64(-1).encode(to: &encoder)
        UInt16(0x1234).encode(to: &encoder)
        UInt8(0x42).encode(to: &encoder)
        let base: [UInt8] = [UInt8](encoder.output)
        #expect(span == base)
    }

    @Test static func compactString() {
        let str: String = "hello-world"
        let utf8: [UInt8] = [UInt8](str.utf8)

        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 64, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var s: SpanEncoder = .init(raw)
        s.append(UInt8(0)) // .compact
        utf8.withUnsafeBytes { (p: UnsafeRawBufferPointer) in s.append(copying: p) }
        s.append(UInt8(0x00))
        let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))

        var encoder: BufferEncoder = .init(capacity: 64)
        str.encode(to: &encoder)
        let base: [UInt8] = [UInt8](encoder.output)
        #expect(span == base)

        var decoder: BufferDecoder = .init(span[...])
        #expect((try? String.decode(from: &decoder)) == str)
    }

    @Test static func emptyString() {
        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 8, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var s: SpanEncoder = .init(raw)
        s.append(UInt8(2)) // .none
        let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))

        var encoder: BufferEncoder = .init(capacity: 8)
        "".encode(to: &encoder)
        let base: [UInt8] = [UInt8](encoder.output)
        #expect(span == base)
    }

    @Test static func longString() {
        // > 256 UTF-8 bytes forces the long format (format byte + UInt32 low + UInt8 high).
        let str: String = String(repeating: "x", count: 300)
        let utf8: [UInt8] = [UInt8](str.utf8)
        let size: UInt64 = .init(utf8.count)

        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 512, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var s: SpanEncoder = .init(raw)
        s.append(UInt8(1)) // .long
        s.appendLittleEndian(UInt32(truncatingIfNeeded: size))
        s.append(UInt8(size >> 32))
        utf8.withUnsafeBytes { (p: UnsafeRawBufferPointer) in s.append(copying: p) }
        let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))

        var encoder: BufferEncoder = .init(capacity: 512)
        str.encode(to: &encoder)
        let base: [UInt8] = [UInt8](encoder.output)
        #expect(span == base)

        var decoder: BufferDecoder = .init(span[...])
        #expect((try? String.decode(from: &decoder)) == str)
    }

    @Test static func boundaryCompact256() {
        //  Exactly 256 UTF-8 bytes is the largest COMPACT string (format 0 + bytes + NUL).
        let str: String = String(repeating: "x", count: 256)
        let utf8: [UInt8] = [UInt8](str.utf8)
        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 512, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var s: SpanEncoder = .init(raw)
        s.append(UInt8(0)) // .compact
        utf8.withUnsafeBytes { (p: UnsafeRawBufferPointer) in s.append(copying: p) }
        s.append(UInt8(0x00))
        let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))

        var encoder: BufferEncoder = .init(capacity: 512)
        str.encode(to: &encoder)
        let base: [UInt8] = [UInt8](encoder.output)
        #expect(span == base)
        #expect(base.first == 0) // confirms BufferEncoder also chose compact at 256
        var decoder: BufferDecoder = .init(span[...])
        #expect((try? String.decode(from: &decoder)) == str)
    }

    @Test static func boundaryLong257() {
        //  257 UTF-8 bytes crosses into the LONG format (format 1 + UInt32 low + UInt8 high).
        let str: String = String(repeating: "x", count: 257)
        let utf8: [UInt8] = [UInt8](str.utf8)
        let size: UInt64 = .init(utf8.count)
        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 512, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var s: SpanEncoder = .init(raw)
        s.append(UInt8(1)) // .long
        s.appendLittleEndian(UInt32(truncatingIfNeeded: size))
        s.append(UInt8(size >> 32))
        utf8.withUnsafeBytes { (p: UnsafeRawBufferPointer) in s.append(copying: p) }
        let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))

        var encoder: BufferEncoder = .init(capacity: 512)
        str.encode(to: &encoder)
        let base: [UInt8] = [UInt8](encoder.output)
        #expect(span == base)
        #expect(base.first == 1) // confirms BufferEncoder also chose long at 257
        var decoder: BufferDecoder = .init(span[...])
        #expect((try? String.decode(from: &decoder)) == str)
    }

    @Test static func embeddedNUL() {
        //  A short string containing a NUL cannot use the NUL-terminated compact format,
        //  so it must fall to long even though it is well under 256 bytes.
        let str: String = "ab\u{0}cd"
        let utf8: [UInt8] = [UInt8](str.utf8)
        let size: UInt64 = .init(utf8.count)
        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 64, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var s: SpanEncoder = .init(raw)
        s.append(UInt8(1)) // .long (compact disallowed by the embedded NUL)
        s.appendLittleEndian(UInt32(truncatingIfNeeded: size))
        s.append(UInt8(size >> 32))
        utf8.withUnsafeBytes { (p: UnsafeRawBufferPointer) in s.append(copying: p) }
        let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))

        var encoder: BufferEncoder = .init(capacity: 64)
        str.encode(to: &encoder)
        let base: [UInt8] = [UInt8](encoder.output)
        #expect(span == base)
        #expect(base.first == 1) // BufferEncoder must also choose long for an embedded NUL
        var decoder: BufferDecoder = .init(span[...])
        #expect((try? String.decode(from: &decoder)) == str)
    }

    @Test static func optionalDiscriminant() {
        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 32, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var s: SpanEncoder = .init(raw)
        s.append(UInt8(1)) // some
        s.appendLittleEndian(UInt64(7))
        s.append(UInt8(0)) // none
        let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))

        var encoder: BufferEncoder = .init(capacity: 32)
        (UInt64(7) as UInt64?).encode(to: &encoder)
        (nil as UInt64?).encode(to: &encoder)
        let base: [UInt8] = [UInt8](encoder.output)
        #expect(span == base)
    }

    @Test static func byteCountAndFreeCapacity() {
        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 16, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var s: SpanEncoder = .init(raw)
        #expect(s.byteCount == 0)
        #expect(s.freeCapacity == 16)
        s.appendLittleEndian(UInt64(0))
        #expect(s.byteCount == 8)
        #expect(s.freeCapacity == 8)
        #expect(s.finalize() == 8)
    }
}
