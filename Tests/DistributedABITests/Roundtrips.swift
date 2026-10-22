import DistributedABI
import Testing

@Suite enum Roundtrips {
    @Test(arguments: Self.integers) static func Integers(
        _ value: any Transferable & Equatable
    ) throws {
        try Self.roundtrip(value)
    }

    @Test(
        arguments: [
            true,
            false,
            0.0 as Double,
            1.5 as Double,
            -.infinity as Double,
            .greatestFiniteMagnitude as Double,
            .leastNonzeroMagnitude as Double,
            0.0 as Float,
            -19.89 as Float,
            .infinity as Float,
            .leastNonzeroMagnitude as Float,
        ] as [any Transferable & Equatable]
    ) static func Scalars(_ value: any Transferable & Equatable) throws {
        try Self.roundtrip(value)
    }

    /// Equality cannot see a NaN payload or the sign of zero, so these compare bit patterns.
    @Test(
        arguments: [
            Double.nan.bitPattern,
            Double.signalingNaN.bitPattern,
            (-Double.nan).bitPattern,
            0x7ff0_0000_0000_0001,
            (-0.0 as Double).bitPattern,
        ]
    ) static func DoubleBitPatterns(_ bitPattern: UInt64) throws {
        let value: Double = .init(bitPattern: bitPattern)
        #expect(try Double.decode(.init(transferring: value)).bitPattern == bitPattern)
    }

    @Test(
        arguments: [
            Float.nan.bitPattern,
            Float.signalingNaN.bitPattern,
            0x7f80_0001,
            (-0.0 as Float).bitPattern,
        ]
    ) static func FloatBitPatterns(_ bitPattern: UInt32) throws {
        let value: Float = .init(bitPattern: bitPattern)
        #expect(try Float.decode(.init(transferring: value)).bitPattern == bitPattern)
    }

    @Test(
        arguments: [
            "",
            "Hi Barbie!",
            "¡Hola Barbie!",
            "¡Hola\0Barbie!",
            "👩‍👩‍👧‍👦",
            String.init(repeating: "abcdefghijklmnopqrstuvwxyz", count: 100),
            "--substring--".dropFirst(2).dropLast(2),
        ] as [any Transferable & Equatable]
    ) static func Strings(_ value: any Transferable & Equatable) throws {
        try Self.roundtrip(value)
    }

    @Test(
        arguments: [
            [] as [String],
            [""],
            ["", "a", "abc"],
            [[], [""], ["", "a"], ["abc"]] as [[String]],
            [0, 1, .min, .max] as [Int],
            [nil, 0, nil] as [Int?],
            ["a", nil, ""] as [String?],
            [true, false, true],
            [1, 2, 3, 4][1...] as ArraySlice<Int>,
            [] as Set<String>,
            ["", "a", "abc"] as Set<String>,
            [[], [""], ["", "a"]] as Set<Set<String>>,
            [1, 2, 3] as Set<Int>,
            [:] as [String: String],
            ["": "", "a": "b", "abc": "def"] as [String: String],
            [[:]: [:], ["a": "b"]: ["c": "d"]] as [[String: String]: [String: String]],
            [1: ["a": 1, "b": .min], 2: [:]] as [Int: [String: Int]],
            [.buy, .sell, .buy] as [Side],
            [.primary, .dark] as [Venue],
        ] as [any Transferable & Equatable]
    ) static func Collections(_ value: any Transferable & Equatable) throws {
        try Self.roundtrip(value)
    }

    @Test(
        arguments: [
            Side.buy,
            Side.sell,
            Venue.primary,
            Venue.dark,
            Wide.low,
            Wide.high,
            WideSigned.one,
            Result<Int, Failure>.success(42),
            Result<Int, Failure>.failure(.init(code: -1)),
            Result<String, Failure>.success("ok"),
            Result<[String?], Failure>.success(["a", nil]),
            nil as Result<Int, Failure>?,
        ] as [any Transferable & Equatable]
    ) static func Enumerations(_ value: any Transferable & Equatable) throws {
        try Self.roundtrip(value)
    }

    @Test(
        arguments: [
            Row.init(bytes: [1, 2, 3]),
            Row.init(bytes: .init(0 ... 255)),
            Identifier.init(7),
            Identifier.init(.max),
            [Identifier.init(1): Row.init(bytes: [9])],
        ] as [any Transferable & Equatable]
    ) static func Contiguous(_ value: any Transferable & Equatable) throws {
        try Self.roundtrip(value)
    }
}
extension Roundtrips {
    /// Every value round-trips alone, as the part of a container, as the element of an array
    /// and wrapped in an optional, and writes exactly the bytes it states each time.
    private static func roundtrip<Value>(_ value: Value) throws
        where Value: Transferable & Equatable {
        let bytes: [UInt8] = .init(transferring: value)
        #expect(bytes.count == value.transferSize)
        #expect(try Value.decode(bytes) == value)

        let framed: [UInt8] = .init(framing: value)
        #expect(framed.count == value.framedTransferSize)
        #expect(try Value.decode(framed: framed) == value)

        let array: [Value] = [value, value]
        let elements: [UInt8] = .init(transferring: array)
        #expect(elements.count == array.transferSize)
        #expect(try [Value].decode(elements) == array)

        let optional: Value? = value
        #expect(try Value?.decode(.init(transferring: optional)) == optional)
    }

    private static func edges<Integer>(
        _: Integer.Type
    ) -> [any Transferable & Equatable] where Integer: FixedWidthInteger & Transferable {
        let values: [Integer] = [
            .min,
            .max,
            0,
            1,
            .init(truncatingIfNeeded: 0x0102_0304_0506_0708 as UInt64),
        ]
        return values
    }

    private static var integers: [any Transferable & Equatable] {
        Self.edges(Int.self)
            + Self.edges(Int8.self)
            + Self.edges(Int16.self)
            + Self.edges(Int32.self)
            + Self.edges(Int64.self)
            + Self.edges(Int128.self)
            + Self.edges(UInt.self)
            + Self.edges(UInt8.self)
            + Self.edges(UInt16.self)
            + Self.edges(UInt32.self)
            + Self.edges(UInt64.self)
            + Self.edges(UInt128.self)
    }
}
