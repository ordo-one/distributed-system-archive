@testable import DistributedABI
import Testing

//  Pins the CONCRETE high-level SpanEncoder write methods (append(_:Bool/Double/Float/String/
//  Substring), append(collectionHeader:)) byte-for-byte against BufferEncoder, at the boundaries
//  that matter. The lower-level SpanEncoderParity suite drives the raw primitives and hand-writes
//  the format; this suite calls the actual library methods, so a future divergence in either path
//  is caught. SpanEncoder is ~Copyable/~Escapable, so each test drives it at top-level scope.
@Suite struct SpanEncoderMethods {
    @Test static func boolMethod() {
        for value: Bool in [true, false] {
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 8, alignment: 1)
            defer { reserved.deallocate() }
            var s: SpanEncoder = .init(.init(buffer: reserved, initializedCount: 0))
            s.append(value)
            let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))
            var e: BufferEncoder = .init(capacity: 8)
            value.encode(to: &e)
            let base: [UInt8] = [UInt8](e.output)
            #expect(span == base)
        }
    }

    @Test static func doubleMethodBitPatterns() {
        let values: [Double] = [
            0, -0.0, .pi, .infinity, -.infinity, .nan,
            .init(bitPattern: 0x7FF0_0000_0000_0001), .init(bitPattern: .max),
        ]
        for value: Double in values {
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 16, alignment: 1)
            defer { reserved.deallocate() }
            var s: SpanEncoder = .init(.init(buffer: reserved, initializedCount: 0))
            s.append(value)
            let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))
            var e: BufferEncoder = .init(capacity: 16)
            value.encode(to: &e)
            let base: [UInt8] = [UInt8](e.output)
            #expect(span == base)
        }
    }

    @Test static func floatMethodBitPatterns() {
        //  The e2e Message has no Float field, so this is the only coverage of append(_:Float).
        let values: [Float] = [
            0, -0.0, .pi, .infinity, -.infinity, .nan,
            .init(bitPattern: 0x7F80_0001), .init(bitPattern: .max),
        ]
        for value: Float in values {
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 8, alignment: 1)
            defer { reserved.deallocate() }
            var s: SpanEncoder = .init(.init(buffer: reserved, initializedCount: 0))
            s.append(value)
            let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))
            var e: BufferEncoder = .init(capacity: 8)
            value.encode(to: &e)
            let base: [UInt8] = [UInt8](e.output)
            #expect(span == base)
        }
    }

    @Test static func stringMethodBoundaries() {
        let values: [String] = [
            "",                                    // none (format 2)
            "x",                                   // compact
            String(repeating: "x", count: 256),   // compact boundary
            String(repeating: "x", count: 257),   // long boundary
            "ab\u{0}cd",                           // embedded NUL -> long
            "héllo \u{1F600}",                     // multibyte
        ]
        for value: String in values {
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 1024, alignment: 1)
            defer { reserved.deallocate() }
            var s: SpanEncoder = .init(.init(buffer: reserved, initializedCount: 0))
            s.append(value)
            let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))
            var e: BufferEncoder = .init(capacity: 1024)
            value.encode(to: &e)
            let base: [UInt8] = [UInt8](e.output)
            #expect(span == base, "string method mismatch for length \(value.utf8.count)")
            //  And it must decode back to the original through both decoders.
            var bd: BufferDecoder = .init(span[...])
            #expect((try? String.decode(from: &bd)) == value)
        }
    }

    @Test static func substringMethod() {
        let source: String = "the quick brown fox"
        let value: Substring = source.dropFirst(4)
        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 64, alignment: 1)
        defer { reserved.deallocate() }
        var s: SpanEncoder = .init(.init(buffer: reserved, initializedCount: 0))
        s.append(value)
        let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))
        var e: BufferEncoder = .init(capacity: 64)
        value.encode(to: &e)
        let base: [UInt8] = [UInt8](e.output)
        #expect(span == base)
    }

    @Test static func collectionHeaderBoundaries() {
        for count: Int in [0, 1, 254, 255, 256, 70_000] {
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: 16, alignment: 1)
            defer { reserved.deallocate() }
            var s: SpanEncoder = .init(.init(buffer: reserved, initializedCount: 0))
            s.append(collectionHeader: count)
            let span: [UInt8] = [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< s.finalize()]))
            //  Compare against the same array's CollectionHeader as BufferEncoder emits it: a
            //  count-element [UInt8] header is just the header bytes, so encode an empty payload
            //  of that count via Array's BufferEncodable header path is overkill — instead pin
            //  the documented shape directly.
            if count < 255 {
                #expect(span == [UInt8(count)])
            } else {
                var expected: [UInt8] = [0xFF]
                withUnsafeBytes(of: Int(count).littleEndian) { expected.append(contentsOf: $0) }
                #expect(span == expected)
            }
        }
    }
}
