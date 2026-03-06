import OrdoDistributedABI
import Testing

@Suite struct Roundtripping {
    @Test static func RoundtripNil() throws {
        try Self.roundtrip(nil as Bool?)
        try Self.roundtrip(nil as Float?)
        try Self.roundtrip(nil as Double?)
        try Self.roundtrip(nil as Int8?)
        try Self.roundtrip(nil as Int16?)
        try Self.roundtrip(nil as Int32?)
        try Self.roundtrip(nil as Int64?)
        try Self.roundtrip(nil as Int?)
        try Self.roundtrip(nil as UInt8?)
        try Self.roundtrip(nil as UInt16?)
        try Self.roundtrip(nil as UInt32?)
        try Self.roundtrip(nil as UInt64?)
        try Self.roundtrip(nil as UInt64?)
        try Self.roundtrip(nil as UInt?)
        try Self.roundtrip(nil as String?)
    }

    @Test(
        arguments: [true, false]
    ) static func RoundtripBool(_ value: Bool) throws {
        try Self.roundtrip(value)
    }

    @Test(
        arguments: [.min, -13, 0, 13, .max]
    ) static func RoundtripInt(_ value: Int) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as Int?)
    }

    @Test(
        arguments: [-.infinity, -13, 0, 13, 19.89, .infinity]
    ) static func RoundtripDouble(_ value: Double) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as Double?)
    }
    @Test static func RoundtripDoubleQuietNaN() throws {
        #expect(try Self.reencode(Double.nan).isNaN)
    }
    @Test static func RoundtripDoubleSignalingNaN() throws {
        #expect(try Self.reencode(Double.signalingNaN).isSignalingNaN)
    }

    @Test(
        arguments: [
            "",
            "Hi Barbie!",
            "¡Hola Barbie!",
        ]
    ) static func RoundtripString(_ value: String) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as String?)
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
