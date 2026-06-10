import Testing
@testable import DistributedABI

@Suite struct HostileInput {
    /// A 9-byte collection header can claim an arbitrary element count. Decoding must
    /// never trap or pre-allocate based on that count before the payload is validated.
    @Test static func hugeCountDoesNotAbort() throws {
        // 0xFF marker + Int.max little-endian, with no element payload.
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]
        var input: BufferDecoder = .init(bytes[...])
        #expect(throws: BufferDecodingError.self) {
            let _: [UInt8] = try .decode(from: &input)
        }
    }
    @Test static func negativeCountDoesNotTrap() throws {
        // 0xFF marker + (-1) little-endian.
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        var input: BufferDecoder = .init(bytes[...])
        #expect(throws: BufferDecodingError.self) {
            let _: [UInt8] = try .decode(from: &input)
        }
    }
    @Test static func amplificationCountDoesNotPreallocate() throws {
        // 0xFF marker + 2^30 little-endian, with no element payload: must not allocate 1 GiB.
        let bytes: [UInt8] = [0xFF, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00]
        var input: BufferDecoder = .init(bytes[...])
        #expect(throws: BufferDecodingError.self) {
            let _: [UInt8] = try .decode(from: &input)
        }
    }
    @Test static func dictionaryHugeCountDoesNotAbort() throws {
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]
        var input: BufferDecoder = .init(bytes[...])
        #expect(throws: BufferDecodingError.self) {
            let _: [UInt8: UInt8] = try .decode(from: &input)
        }
    }
}
