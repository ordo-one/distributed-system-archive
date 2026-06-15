import DistributedABI
import Testing

@Suite enum WireFormatCheck {
    @Test static func Empty() {
        #expect(Self.encode("") == [2])
    }
    @Test static func CompactShort() {
        #expect(Self.encode("ab") == [0, 0x61, 0x62, 0])
    }
    @Test static func CompactBoundary256() {
        let string: String = .init(repeating: "a", count: 256)
        let expected: [UInt8] = [0] + Array(repeating: 0x61, count: 256) + [0]
        #expect(Self.encode(string) == expected)
    }
    @Test static func LongBoundary257() {
        let string: String = .init(repeating: "a", count: 257)
        let expected: [UInt8] = [1, 1, 1, 0, 0, 0] + Array(repeating: 0x61, count: 257)
        #expect(Self.encode(string) == expected)
    }
    @Test static func LongEmbeddedNul() {
        let string: String = "a\u{0}b"
        let expected: [UInt8] = [1, 3, 0, 0, 0, 0, 0x61, 0x00, 0x62]
        #expect(Self.encode(string) == expected)
    }
    @Test static func LongRoundtrip() throws {
        let string: String = .init(repeating: "xyz\u{0}", count: 100)
        let decoded: String = try .decode(Self.encode(string))
        #expect(decoded == string)
    }
}
extension WireFormatCheck {
    private static func encode(_ string: String) -> [UInt8] {
        string.encoded()
    }
}
