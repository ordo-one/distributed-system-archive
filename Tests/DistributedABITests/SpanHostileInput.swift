import Testing
@testable import DistributedABI

/// DoS-hardening tests for the zero-copy ``SpanDecoder``, mirroring
/// ``HostileInput`` for the `ArraySlice`-backed decoder. A hostile collection
/// header can claim an arbitrary element count; decoding must throw a
/// ``BufferDecodingError`` rather than trap or pre-allocate gigabytes before any
/// element payload has been validated.
@Suite struct SpanHostileInput {
    /// Decodes `bytes` as `T` through a `SpanDecoder` over borrowed memory,
    /// rethrowing whatever the decoder throws.
    private static func decode<T>(
        _ type: T.Type, from bytes: [UInt8]
    ) throws -> T where T: SpanDecodable {
        try bytes.withUnsafeBytes {
            (raw: UnsafeRawBufferPointer) throws -> T in
            var input: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
            return try .decode(from: &input)
        }
    }

    /// A 9-byte collection header can claim an arbitrary element count. Decoding must
    /// never trap or pre-allocate based on that count before the payload is validated.
    @Test static func hugeCountDoesNotAbort() throws {
        // 0xFF marker + Int.max little-endian, with no element payload.
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]
        #expect(throws: BufferDecodingError.self) {
            let _: [UInt8] = try Self.decode([UInt8].self, from: bytes)
        }
    }
    @Test static func negativeCountDoesNotTrap() throws {
        // 0xFF marker + (-1) little-endian.
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        #expect(throws: BufferDecodingError.self) {
            let _: [UInt8] = try Self.decode([UInt8].self, from: bytes)
        }
    }
    @Test static func amplificationCountDoesNotPreallocate() throws {
        // 0xFF marker + 2^30 little-endian, with no element payload: must not allocate 1 GiB.
        let bytes: [UInt8] = [0xFF, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00]
        #expect(throws: BufferDecodingError.self) {
            let _: [UInt8] = try Self.decode([UInt8].self, from: bytes)
        }
    }
    @Test static func dictionaryHugeCountDoesNotAbort() throws {
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]
        #expect(throws: BufferDecodingError.self) {
            let _: [UInt8: UInt8] = try Self.decode([UInt8: UInt8].self, from: bytes)
        }
    }
    @Test static func setHugeCountDoesNotAbort() throws {
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]
        #expect(throws: BufferDecodingError.self) {
            let _: Set<UInt8> = try Self.decode(Set<UInt8>.self, from: bytes)
        }
    }
    @Test static func setNegativeCountDoesNotTrap() throws {
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        #expect(throws: BufferDecodingError.self) {
            let _: Set<UInt8> = try Self.decode(Set<UInt8>.self, from: bytes)
        }
    }
    @Test static func dictionaryAmplificationDoesNotPreallocate() throws {
        let bytes: [UInt8] = [0xFF, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00]
        #expect(throws: BufferDecodingError.self) {
            let _: [UInt8: UInt8] = try Self.decode([UInt8: UInt8].self, from: bytes)
        }
    }
    /// A truncated `.long` string header claiming a huge length must throw, not
    /// over-read or pre-allocate.
    @Test static func longStringHugeLengthDoesNotAbort() throws {
        // format .long (1) + low UInt32 = 0xFFFFFFFF + high UInt8 = 0xFF, no payload.
        let bytes: [UInt8] = [1, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        #expect(throws: BufferDecodingError.self) {
            let _: String = try Self.decode(String.self, from: bytes)
        }
    }
    /// An invalid `String.BinaryFormat` discriminant must throw rather than trap.
    @Test static func invalidStringFormatThrows() throws {
        let bytes: [UInt8] = [9]
        #expect(throws: BufferDecodingError.self) {
            let _: String = try Self.decode(String.self, from: bytes)
        }
    }
    /// An invalid `Optional.BinaryFormat` discriminant must throw rather than trap.
    @Test static func invalidOptionalFormatThrows() throws {
        let bytes: [UInt8] = [9]
        #expect(throws: BufferDecodingError.self) {
            let _: Int? = try Self.decode(Int?.self, from: bytes)
        }
    }
}
