import DistributedABI
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
            "¡Hola\0Barbie!",
            String.init(repeating: "abcdefghijklmnopqrstuvwxyz", count: 100),
        ]
    ) static func RoundtripString(_ value: String) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as String?)
    }

    @Test(
        arguments: [
            [],
            [""],
            ["", "a", "abc"],
        ]
    ) static func RoundtripArray(_ value: [String]) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as [String]?)
    }

    @Test(
        arguments: [
            [],
            [[]],
            [[""]],
            [[""], [""]],
            [["", "a"], [], ["abc"]],
        ]
    ) static func RoundtripArrayNested(_ value: [[String]]) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as [[String]]?)
    }

    @Test(
        arguments: [
            [],
            [""],
            ["", "a", "abc"],
        ]
    ) static func RoundtripSet(_ value: Set<String>) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as Set<String>?)
    }

    @Test(
        arguments: [
            [],
            [[]],
            [[""]],
            [[""], [""]],
            [["", "a"], [], ["abc"]],
        ]
    ) static func RoundtripSetOfSets(_ value: Set<Set<String>>) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as Set<Set<String>>?)
    }

    @Test(
        arguments: [
            [:],
            ["": ""],
            ["": "a"],
            ["a": ""],
            ["": "a", "a": "b", "abc": "def"],
        ]
    ) static func RoundtripDictionary(_ value: [String: String]) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as [String: String]?)
    }

    @Test(
        arguments: [
            [:],
            [[:]: [:]],
            [["": ""]: ["": ""]],
            [["a": "b"]: ["c": "d"]],
            [["a": "b"]: ["c": "d"], ["x": "y"]: ["z": "w"]],
        ]
    ) static func RoundtripDictionaryOfDictionaries(
        _ value: [[String: String]: [String: String]]
    ) throws {
        try Self.roundtrip(value)
        try Self.roundtrip(value as [[String: String]: [String: String]]?)
    }

    @Test(
        arguments: [0, 1, 255, 256, 1000]
    ) static func RoundtripVariableLengthBytes(
        _ length: Int
    ) throws {
        let value: Roundtripping.VariableLengthBytes = .create(length: length)
        try Self.roundtrip(value)
        try Self.roundtrip(value as Roundtripping.VariableLengthBytes?)
    }
}
extension Roundtripping {
    private static func reencode<T>(
        _ original: T
    ) throws -> T where T: BufferEncodable & BufferDecodable & Equatable {
        var encoder: BufferEncoder = .init(preallocated: [])
        try original.encode(to: &encoder)
        var decoder: BufferDecoder = .init(encoder.output)
        let decoded: T = try .decode(from: &decoder)
        try decoder.finish()
        return decoded
    }
    private static func roundtrip<T>(
        _ original: T
    ) throws where T: BufferEncodable & BufferDecodable & Equatable {
        #expect(try self.reencode(original) == original)
    }
}
