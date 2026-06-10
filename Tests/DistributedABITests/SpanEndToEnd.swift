@testable import DistributedABI
import Testing

//  END-TO-END test of the real encode -> wire -> decode path through LIBRARY code.
//
//  A representative message (a mix of UInt64, UInt64?, Bool, Double, a compact String, a
//  257-byte long String, an empty String, and a small [UInt64] collection field written via
//  `SpanEncoder.append(collectionHeader:)` + a loop) is encoded straight into a caller-
//  reserved `UnsafeMutableRawBufferPointer` through the new concrete `SpanEncoder` write
//  methods. We then:
//
//  (a) assert the bytes equal what `BufferEncoder` produces for the SAME logical fields, in
//      the SAME order (byte-for-byte wire parity), and
//  (b) decode the bytes back through BOTH `BufferDecoder` and `SpanDecoder` and assert the
//      decoded values equal the originals.
//
//  This exercises the production wire format end-to-end: every byte is laid out by library
//  `SpanEncoder` methods (no hand-written format logic), and both decode paths must agree.
//
//  NOTE: `SpanEncoder` is `~Copyable`/`~Escapable`. The collection field is written by
//  computing the element bytes, then writing the header + the per-element little-endian
//  values through library methods at top-level encoder scope.

@Suite struct SpanEndToEnd {
    /// The representative message. Field order is fixed and shared by the SpanEncoder encode,
    /// the BufferEncoder reference encode, and both decoders.
    struct Message: Equatable {
        var id: UInt64
        var maybe: UInt64?       // .some
        var absent: UInt64?      // .none
        var flag: Bool
        var ratio: Double
        var short: String        // compact
        var long: String         // 257 bytes -> long format
        var empty: String        // .none format
        var values: [UInt64]     // collection: header + elements

        static let sample: Message = .init(
            id: 0x0102_0304_0506_0708,
            maybe: 0xCAFE_F00D,
            absent: nil,
            flag: true,
            ratio: 3.141592653589793,
            short: "hello-span",
            long: String(repeating: "L", count: 257),
            empty: "",
            values: [1, 2, 3, 0xFFFF_FFFF_FFFF_FFFF, 0]
        )

        //  -- Reference encode through the production [UInt8] BufferEncoder. --
        func encode(to output: inout BufferEncoder) {
            self.id.encode(to: &output)
            self.maybe.encode(to: &output)
            self.absent.encode(to: &output)
            self.flag.encode(to: &output)
            self.ratio.encode(to: &output)
            self.short.encode(to: &output)
            self.long.encode(to: &output)
            self.empty.encode(to: &output)
            //  Collection: the production [UInt8] path encodes `[UInt64]` via the
            //  RangeReplaceableCollection conformance (CollectionHeader + each element). We
            //  spell that out here so the reference bytes are unambiguous and match the
            //  SpanEncoder side field-for-field.
            CollectionHeader(count: self.values.count).encode(to: &output)
            for v: UInt64 in self.values {
                v.encode(to: &output)
            }
        }

        //  -- Encode through the new LIBRARY SpanEncoder concrete methods. --
        func encode(to output: inout SpanEncoder) {
            output.appendLittleEndian(self.id)
            //  Optional discriminant byte (Optional.BinaryFormat: .none=0, .some=1) then the
            //  wrapped value — the caller owns the 0/1 byte (no generic Optional in-library).
            if let maybe: UInt64 = self.maybe {
                output.append(UInt8(1))
                output.appendLittleEndian(maybe)
            } else {
                output.append(UInt8(0))
            }
            if let absent: UInt64 = self.absent {
                output.append(UInt8(1))
                output.appendLittleEndian(absent)
            } else {
                output.append(UInt8(0))
            }
            output.append(self.flag)
            output.append(self.ratio)
            output.append(self.short)
            output.append(self.long)
            output.append(self.empty)
            //  Collection: write the header through the library, then loop calling the leaf
            //  method per element (no generic dispatch — see SpanEncoder's doc comment).
            output.append(collectionHeader: self.values.count)
            for v: UInt64 in self.values {
                output.appendLittleEndian(v)
            }
        }

        //  -- Decode through the production ArraySlice path. --
        static func decode(from input: inout BufferDecoder) throws -> Message {
            let id: UInt64 = try .decode(from: &input)
            let maybe: UInt64? = try .decode(from: &input)
            let absent: UInt64? = try .decode(from: &input)
            let flag: Bool = try .decode(from: &input)
            let ratio: Double = try .decode(from: &input)
            let short: String = try .decode(from: &input)
            let long: String = try .decode(from: &input)
            let empty: String = try .decode(from: &input)
            let values: [UInt64] = try .decode(from: &input)
            return .init(
                id: id, maybe: maybe, absent: absent, flag: flag, ratio: ratio,
                short: short, long: long, empty: empty, values: values
            )
        }

        //  -- Decode through the zero-copy SpanDecoder path. --
        static func decode(from input: inout SpanDecoder) throws -> Message {
            let id: UInt64 = try .decode(from: &input)
            let maybe: UInt64? = try .decode(from: &input)
            let absent: UInt64? = try .decode(from: &input)
            let flag: Bool = try .decode(from: &input)
            let ratio: Double = try .decode(from: &input)
            let short: String = try .decode(from: &input)
            let long: String = try .decode(from: &input)
            let empty: String = try .decode(from: &input)
            let values: [UInt64] = try .decode(from: &input)
            return .init(
                id: id, maybe: maybe, absent: absent, flag: flag, ratio: ratio,
                short: short, long: long, empty: empty, values: values
            )
        }

        /// Closed-form wire size, mirroring the field-by-field library layout, so the caller
        /// can reserve EXACTLY the right region.
        var encodedSize: Int {
            var n: Int = 8                                  // id
            n += (self.maybe == nil ? 1 : 1 + 8)            // maybe
            n += (self.absent == nil ? 1 : 1 + 8)           // absent
            n += 1                                          // flag (Bool)
            n += 8                                          // ratio (Double bitPattern)
            n += Self.stringSize(self.short)
            n += Self.stringSize(self.long)
            n += Self.stringSize(self.empty)
            //  Collection header: 1 byte if count < 255, else 0xFF + 8-byte Int.
            n += (self.values.count < 255 ? 1 : 1 + 8)
            n += 8 * self.values.count                      // UInt64 elements
            return n
        }

        static func stringSize(_ s: String) -> Int {
            let count: Int = s.utf8.count
            if count == 0 { return 1 }
            if count <= 256 && !s.utf8.contains(0) { return 2 + count }
            return 6 + count
        }
    }

    /// Encode the sample message through the LIBRARY SpanEncoder into a reserved region.
    static func spanEncodedBytes(_ message: Message) -> [UInt8] {
        let size: Int = message.encodedSize
        let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: size, alignment: 1)
        defer { reserved.deallocate() }
        let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
        var encoder: SpanEncoder = .init(raw)
        message.encode(to: &encoder)
        let written: Int = encoder.finalize()
        return [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< written]))
    }

    /// Encode the sample message through the reference BufferEncoder.
    static func bufferEncodedBytes(_ message: Message) -> [UInt8] {
        var encoder: BufferEncoder = .init(capacity: message.encodedSize)
        message.encode(to: &encoder)
        return [UInt8](encoder.output)
    }

    @Test static func bytesMatchBufferEncoder() {
        let message: Message = .sample
        let viaSpan: [UInt8] = Self.spanEncodedBytes(message)
        let viaBuffer: [UInt8] = Self.bufferEncodedBytes(message)
        #expect(viaSpan == viaBuffer, "SpanEncoder bytes diverged from BufferEncoder")
        //  The reserved size pass must have predicted the exact extent.
        #expect(viaSpan.count == message.encodedSize)
    }

    @Test static func roundTripThroughBufferDecoder() throws {
        let message: Message = .sample
        let bytes: [UInt8] = Self.spanEncodedBytes(message)
        var decoder: BufferDecoder = .init(bytes[...])
        let decoded: Message = try .decode(from: &decoder)
        try decoder.finish()
        #expect(decoded == message, "BufferDecoder did not round-trip the SpanEncoder bytes")
    }

    @Test static func roundTripThroughSpanDecoder() throws {
        let message: Message = .sample
        let bytes: [UInt8] = Self.spanEncodedBytes(message)
        let decoded: Message = try bytes.withUnsafeBytes {
            (raw: UnsafeRawBufferPointer) throws -> Message in
            var decoder: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
            let value: Message = try Message.decode(from: &decoder)
            try decoder.finish()
            return value
        }
        #expect(decoded == message, "SpanDecoder did not round-trip the SpanEncoder bytes")
    }

    /// Sanity: the long field really crossed into the long format and the short field stayed
    /// compact, so the test actually exercises both string formats.
    @Test static func stringFormatsExercised() {
        let bytes: [UInt8] = Self.spanEncodedBytes(.sample)
        //  Layout up to the strings: id(8) + maybe(1+8) + absent(1) + flag(1) + ratio(8) = 27.
        //  Byte 27 is the `short` format byte; it must be 0 (compact).
        #expect(bytes[27] == 0, "short string should be compact (format 0)")
        //  short = "hello-span" is 10 UTF-8 bytes + 1 format + 1 NUL = 12; long format byte at
        //  27 + 12 = 39 must be 1 (long).
        #expect(bytes[39] == 1, "long string should be long (format 1)")
    }
}
