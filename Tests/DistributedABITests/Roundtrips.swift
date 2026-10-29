import DistributedABI
import Testing
#if _runtime(_ObjC)
import Foundation
#endif

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

    #if _runtime(_ObjC)
    /// A string bridged from an `NSString` whose storage is UTF-16 is transcoded on the way,
    /// and must take the same bytes as the native string with the same contents; so must a
    /// substring of it.
    @Test(arguments: [1, 16, 100_000]) static func BridgedStrings(_ count: Int) throws {
        let native: String = .init(repeating: "é", count: count)
        let string: String = try Self.bridged(native)
        try #require(!string.isContiguousUTF8)
        #expect([UInt8].init(transferring: string) == .init(transferring: native))
        try Self.roundtrip(string)

        let suffix: Substring = string.suffix(1)
        try #require(!suffix.isContiguousUTF8)
        #expect([UInt8].init(transferring: suffix) == [2, 0xc3, 0xa9])
        try Self.roundtrip(suffix)
    }
    #endif

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
            [] as ContiguousArray<String>,
            ["", "a", "abc"] as ContiguousArray<String>,
            [0, 1, .min, .max] as ContiguousArray<Int>,
            [] as Batch<String>,
            ["", "a", "abc"] as Batch<String>,
            [0, 1, .min, .max] as Batch<Int>,
            [] as Set<String>,
            ["", "a", "abc"] as Set<String>,
            [[], [""], ["", "a"]] as Set<Set<String>>,
            [1, 2, 3] as Set<Int>,
            [:] as [String: String],
            ["": "", "a": "b", "abc": "def"] as [String: String],
            [[:]: [:], ["a": "b"]: ["c": "d"]] as [[String: String]: [String: String]],
            [1: ["a": 1, "b": .min], 2: [:]] as [Int: [String: Int]],
            [:] as Ledger<String, Int>,
            ["a": 1, "": .min, "a": 2] as Ledger<String, Int>,
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
    /// Every value round-trips alone, as the element of an array, as the element of a
    /// contiguous array, which takes the array’s bytes, and wrapped in an optional, and writes
    /// exactly the bytes it states each time.
    private static func roundtrip<Value>(_ value: Value) throws
        where Value: Transferable & Equatable {
        let bytes: [UInt8] = .init(transferring: value)
        #expect(bytes.count == value.transferSize)
        #expect(try Value.decode(bytes) == value)

        let array: [Value] = [value, value]
        let elements: [UInt8] = .init(transferring: array)
        #expect(elements.count == array.transferSize)
        #expect(try [Value].decode(elements) == array)

        let contiguous: ContiguousArray<Value> = .init(array)
        #expect([UInt8].init(transferring: contiguous) == elements)
        #expect(contiguous.transferSize == elements.count)
        #expect(try ContiguousArray<Value>.decode(elements) == contiguous)

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

    #if _runtime(_ObjC)
    /// The same contents as `native`, bridged lazily from an `NSString` that stores them as
    /// UTF-16.
    private static func bridged(_ native: String) throws -> String {
        let bytes: [UInt8] = native.utf16.flatMap {
            [UInt8.init(truncatingIfNeeded: $0), UInt8.init(truncatingIfNeeded: $0 >> 8)]
        }
        let string: NSString = try #require(
            NSString.init(
                data: Data.init(bytes),
                encoding: String.Encoding.utf16LittleEndian.rawValue
            )
        )
        return string as String
    }
    #endif

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
