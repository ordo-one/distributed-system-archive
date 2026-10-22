import DistributedABI
import Testing

@Suite enum WireFormat {
    /// The bytes of every standard conformance, both ways: the value writes exactly these, and
    /// reads back from them.
    @Test(
        arguments: [
            // integers: fixed width, little-endian
            (1 as Int, [1, 0, 0, 0, 0, 0, 0, 0]),
            (-1 as Int8, [0xff]),
            (0x0102 as Int16, [0x02, 0x01]),
            (0xdead_beef as UInt32, [0xef, 0xbe, 0xad, 0xde]),
            (0x0102_0304_0506_0708 as UInt64, [8, 7, 6, 5, 4, 3, 2, 1]),
            (1 as UInt128, [1] + [UInt8].init(repeating: 0, count: 15)),
            // one byte, 0 or 1
            (false, [0]),
            (true, [1]),
            // the bit pattern, little-endian
            (1.0 as Float, [0x00, 0x00, 0x80, 0x3f]),
            (1.0 as Double, [0, 0, 0, 0, 0, 0, 0xf0, 0x3f]),
            // UTF-8 as it is: no length, no terminator, no format byte
            ("", []),
            ("ab", [0x61, 0x62]),
            ("a\0b", [0x61, 0x00, 0x62]),
            ("é", [0xc3, 0xa9]),
            ("xaby".dropFirst().dropLast() as Substring, [0x61, 0x62]),
            // a discriminant byte, then the payload as it is
            (nil as Int?, [0]),
            (7 as UInt8?, [1, 7]),
            ("ab" as String?, [1, 0x61, 0x62]),
            (Result<UInt8, Failure>.success(9), [0, 9]),
            (Result<UInt8, Failure>.failure(.init(code: 2)), [1, 2, 0, 0, 0]),
            // a count, then fixed-size elements packed
            ([] as [UInt8], [0]),
            ([1, 2] as [Int16], [2, 1, 0, 2, 0]),
            ([true] as [Bool], [1, 1]),
            ([.sell, .buy] as [Side], [2, 0xff, 0x01]),
            // a count, then variable-size elements each behind a ULEB128 length
            (["ab", ""], [2, 2, 0x61, 0x62, 0]),
            (["a", nil] as [String?], [2, 2, 1, 0x61, 1, 0]),
            ([[1], []] as [[UInt8]], [2, 2, 1, 1, 1, 0]),
            ([5] as Set<UInt8>, [1, 5]),
            ([7: "x"] as [UInt8: String], [1, 7, 1, 0x78]),
            (["k": 3] as [String: UInt16], [1, 1, 0x6b, 3, 0]),
            // the count is ULEB128: one byte up to 127, two up to 16,383
            ([UInt8].init(repeating: 9, count: 127), [0x7f] + .init(repeating: 9, count: 127)),
            ([UInt8].init(repeating: 9, count: 128), [0x80, 0x01] + .init(repeating: 9, count: 128)),
            (
                [UInt8].init(repeating: 9, count: 16_384),
                [0x80, 0x80, 0x01] + .init(repeating: 9, count: 16_384)
            ),
            // an integer raw value travels as the raw value
            (Side.sell, [0xff]),
            (Venue.primary, [0x02, 0x01]),
            // a contiguous value lends its bytes unchanged
            (Row.init(bytes: [3, 1, 4]), [3, 1, 4]),
            (Identifier.init(0x0102), [2, 1, 0, 0, 0, 0, 0, 0]),
            // packed when the contiguous type states a fixed size, framed when it does not
            ([.init(1), .init(2)] as [Identifier], [2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]),
            ([.init(bytes: [3]), .init(bytes: [1, 4])] as [Row], [2, 1, 3, 2, 1, 4]),
        ] as [(any Transferable & Equatable, [UInt8])]
    ) static func Bytes(_ value: any Transferable & Equatable, _ expected: [UInt8]) throws {
        try Self.check(value, expected)
    }

    /// Every standard conformance states the fixed size its wire form has, or none, and an
    /// array packs its elements behind the count exactly when the size is fixed. The sizes
    /// and the bytes are written out, so a conformance that loses or gains a fixed size
    /// fails here even though it still round-trips.
    @Test(
        arguments: [
            // integers: their width, little-endian
            Packing.init([1, -2] as [Int], fixed: 8, [2, 1, 0, 0, 0, 0, 0, 0, 0] + [0xfe] + .init(repeating: 0xff, count: 7)),
            Packing.init([1, -2] as [Int8], fixed: 1, [2, 1, 0xfe]),
            Packing.init([0x0102, -2] as [Int16], fixed: 2, [2, 2, 1, 0xfe, 0xff]),
            Packing.init([0x0102_0304, -2] as [Int32], fixed: 4, [2, 4, 3, 2, 1, 0xfe, 0xff, 0xff, 0xff]),
            Packing.init(
                [0x0102_0304_0506_0708, -2] as [Int64],
                fixed: 8,
                [2, 8, 7, 6, 5, 4, 3, 2, 1, 0xfe] + .init(repeating: 0xff, count: 7)
            ),
            Packing.init(
                [1, -2] as [Int128],
                fixed: 16,
                [2, 1] + .init(repeating: 0, count: 15) + [0xfe] + .init(repeating: 0xff, count: 15)
            ),
            Packing.init([1, .max] as [UInt], fixed: 8, [2, 1, 0, 0, 0, 0, 0, 0, 0] + .init(repeating: 0xff, count: 8)),
            Packing.init([1, 0xff] as [UInt8], fixed: 1, [2, 1, 0xff]),
            Packing.init([0x0102, 0xfffe] as [UInt16], fixed: 2, [2, 2, 1, 0xfe, 0xff]),
            Packing.init([0x0102_0304, 0xdead_beef] as [UInt32], fixed: 4, [2, 4, 3, 2, 1, 0xef, 0xbe, 0xad, 0xde]),
            Packing.init([0x0102_0304_0506_0708, 1] as [UInt64], fixed: 8, [2, 8, 7, 6, 5, 4, 3, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0]),
            Packing.init(
                [1, 1 << 64] as [UInt128],
                fixed: 16,
                [2, 1] + .init(repeating: 0, count: 23) + [1] + .init(repeating: 0, count: 7)
            ),
            // one byte, 0 or 1
            Packing.init([true, false], fixed: 1, [2, 1, 0]),
            // the bit pattern, little-endian
            Packing.init([1, -2] as [Float], fixed: 4, [2, 0, 0, 0x80, 0x3f, 0, 0, 0, 0xc0]),
            Packing.init([1, -2] as [Double], fixed: 8, [2, 0, 0, 0, 0, 0, 0, 0xf0, 0x3f, 0, 0, 0, 0, 0, 0, 0, 0xc0]),
            // an integer raw value: the size of the raw value
            Packing.init([.sell, .buy] as [Side], fixed: 1, [2, 0xff, 1]),
            Packing.init([.primary, .dark] as [Venue], fixed: 2, [2, 2, 1, 0xfe, 0xff]),
            // no fixed size: each element behind its ULEB128 length
            Packing.init(["a", ""] as [String], fixed: nil, [2, 1, 0x61, 0]),
            Packing.init(["a"] as [Substring], fixed: nil, [1, 1, 0x61]),
            Packing.init([7, nil] as [UInt8?], fixed: nil, [2, 2, 1, 7, 1, 0]),
            Packing.init([[1], []] as [[UInt8]], fixed: nil, [2, 2, 1, 1, 1, 0]),
            Packing.init([[1][...]] as [ArraySlice<UInt8>], fixed: nil, [1, 2, 1, 1]),
            Packing.init([[5]] as [Set<UInt8>], fixed: nil, [1, 2, 1, 5]),
            Packing.init([[1: 2]] as [[UInt8: UInt8]], fixed: nil, [1, 3, 1, 1, 2]),
            // deliberately none, whether the payloads differ in size
            Packing.init(
                [.success(9), .failure(.init(code: 2))] as [Result<UInt8, Failure>],
                fixed: nil,
                [2, 2, 0, 9, 5, 1, 2, 0, 0, 0]
            ),
            // or have the same fixed size
            Packing.init(
                [.success(9), .failure(.init(code: 2))] as [Result<UInt32, Failure>],
                fixed: nil,
                [2, 5, 0, 9, 0, 0, 0, 5, 1, 2, 0, 0, 0]
            ),
        ]
    ) static func FixedSizes(_ packing: Packing) throws {
        #expect(packing.stated == packing.expected)
        #expect(packing.write() == packing.golden)
        #expect(try packing.read(packing.golden))
    }

    @Test(
        arguments: [
            (0, [0]),
            (1, [1]),
            (127, [0x7f]),
            (128, [0x80, 0x01]),
            (300, [0xac, 0x02]),
            (16_383, [0xff, 0x7f]),
            (16_384, [0x80, 0x80, 0x01]),
            (UInt.init(Int.max), [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f]),
            (.max, [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]),
        ] as [(UInt, [UInt8])]
    ) static func ULEB128Numbers(_ value: UInt, _ expected: [UInt8]) {
        let bytes: [UInt8] = .init(capacity: 10) { $0.append(uleb128: value) }
        #expect(bytes == expected)
        #expect(ULEB128.size(value) == expected.count)
    }
}
extension WireFormat {
    private static func check<Value>(
        _ value: Value,
        _ expected: [UInt8]
    ) throws where Value: Transferable & Equatable {
        #expect([UInt8].init(transferring: value) == expected)
        #expect(value.transferSize == expected.count)
        #expect(try Value.decode(expected) == value)
    }
}
