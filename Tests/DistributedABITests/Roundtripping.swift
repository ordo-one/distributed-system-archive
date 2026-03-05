import DistributedABI
import Testing

@Suite struct Roundtripping {
    @Test static func RoundtripBool() throws {
        try Self.roundtrip(true)
    }

    @Test static func RoundtripInt() throws {
        try Self.roundtrip(13)
    }
    @Test static func RoundtripIntOptional() throws {
        try Self.roundtrip(13 as Int?)
    }

    @Test static func RoundtripDouble() throws {
        try Self.roundtrip(19.89)
    }
    @Test static func RoundtripDoubleInfinity() throws {
        try Self.roundtrip(Double.infinity)
    }
    @Test static func RoundtripDoubleQuietNaN() throws {
        #expect(try Self.reencode(Double.nan).isNaN)
    }
    @Test static func RoundtripDoubleSignalingNaN() throws {
        #expect(try Self.reencode(Double.signalingNaN).isSignalingNaN)
    }

    @Test static func RoundtripString() throws {
        try Self.roundtrip("Hi Barbie!")
    }
    @Test static func RoundtripStringOptional() throws {
        try Self.roundtrip("Hi Barbie!" as String?)
    }
}
extension Roundtripping {
    private static func reencode<T>(_ original: T) throws -> T where T: Serializable & Deserializable & Equatable {
        try original.withUnsafeBytesSerialization(T.init(fromSerializedBuffer:))
    }
    private static func roundtrip<T>(_ original: T) throws where T: Serializable & Deserializable & Equatable {
        #expect(try self.reencode(original) == original)
    }
}
