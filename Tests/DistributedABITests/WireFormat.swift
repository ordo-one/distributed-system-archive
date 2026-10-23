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
            // a ULEB128 length, then the UTF-8 as it is: no terminator, no format byte
            ("", [0]),
            ("ab", [2, 0x61, 0x62]),
            ("a\0b", [3, 0x61, 0x00, 0x62]),
            ("é", [2, 0xc3, 0xa9]),
            ("xaby".dropFirst().dropLast() as Substring, [2, 0x61, 0x62]),
            // a discriminant byte, then the payload as it is
            (nil as Int?, [0]),
            (7 as UInt8?, [1, 7]),
            ("ab" as String?, [1, 2, 0x61, 0x62]),
            (Result<UInt8, Failure>.success(9), [0, 9]),
            (Result<UInt8, Failure>.failure(.init(code: 2)), [1, 2, 0, 0, 0]),
            // a count, then fixed-size elements packed
            ([] as [UInt8], [0]),
            ([1, 2] as [Int16], [2, 1, 0, 2, 0]),
            ([true] as [Bool], [1, 1]),
            ([.sell, .buy] as [Side], [2, 0xff, 0x01]),
            // a count, then variable-size elements one after another, each delimiting itself
            (["ab", ""], [2, 2, 0x61, 0x62, 0]),
            (["a", nil] as [String?], [2, 1, 1, 0x61, 0]),
            ([[1], []] as [[UInt8]], [2, 1, 1, 0]),
            // a contiguous array takes the bytes of an array with the same elements
            ([] as ContiguousArray<UInt8>, [0]),
            ([1, 2] as ContiguousArray<Int16>, [2, 1, 0, 2, 0]),
            (["ab", ""] as ContiguousArray<String>, [2, 2, 0x61, 0x62, 0]),
            // and so does a collection of one’s own, conformed through the public helpers
            ([1, 2] as Batch<Int16>, [2, 1, 0, 2, 0]),
            (["ab", ""] as Batch<String>, [2, 2, 0x61, 0x62, 0]),
            ([5] as Set<UInt8>, [1, 5]),
            (["ab"] as Set<String>, [1, 2, 0x61, 0x62]),
            ([7: "x"] as [UInt8: String], [1, 7, 1, 0x78]),
            (["k": 3] as [String: UInt16], [1, 1, 0x6b, 3, 0]),
            // a keyed collection of one’s own takes the wire form of a dictionary, and this one,
            // which keeps its entries in order, may repeat a key
            ([7: "x"] as Ledger<UInt8, String>, [1, 7, 1, 0x78]),
            (["k": 3, "k": 4] as Ledger<String, UInt16>, [2, 1, 0x6b, 3, 0, 1, 0x6b, 4, 0]),
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
            // a contiguous value lends its bytes unchanged, behind its length when its size varies
            (Row.init(bytes: [3, 1, 4]), [3, 3, 1, 4]),
            // a contiguous value of no bytes is its length alone
            (Blob.init(bytes: []), [0]),
            ([.init(bytes: []), .init(bytes: [7])] as [Blob], [2, 0, 1, 7]),
            // a length of two bytes, as a serialized message of 128 to 16,383 bytes has
            (Row.init(bytes: .init(repeating: 9, count: 128)), [0x80, 0x01] + .init(repeating: 9, count: 128)),
            (
                Row.init(bytes: .init(repeating: 9, count: 16_384)),
                [0x80, 0x80, 0x01] + .init(repeating: 9, count: 16_384)
            ),
            (Identifier.init(0x0102), [2, 1, 0, 0, 0, 0, 0, 0]),
            // packed when the contiguous type states a fixed size, each behind its own length
            // when it does not
            ([.init(1), .init(2)] as [Identifier], [2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]),
            ([.init(bytes: [3]), .init(bytes: [1, 4])] as [Row], [2, 1, 3, 2, 1, 4]),
            // a composite with no fields writes a byte of its own, so it reads back from inside
            // a collection, which refuses a count the bytes remaining could not hold
            (Marker.init(), [0]),
            ([.init(), .init()] as [Marker], [2, 0, 0]),
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
            // no fixed size: each element one after another, delimiting itself
            Packing.init(["a", ""] as [String], fixed: nil, [2, 1, 0x61, 0]),
            Packing.init(["a"] as [Substring], fixed: nil, [1, 1, 0x61]),
            Packing.init([7, nil] as [UInt8?], fixed: nil, [2, 1, 7, 0]),
            Packing.init([[1], []] as [[UInt8]], fixed: nil, [2, 1, 1, 0]),
            Packing.init([[1][...]] as [ArraySlice<UInt8>], fixed: nil, [1, 1, 1]),
            Packing.init([[5]] as [Set<UInt8>], fixed: nil, [1, 1, 5]),
            Packing.init([[1: 2]] as [[UInt8: UInt8]], fixed: nil, [1, 1, 1, 2]),
            // deliberately none, whether the payloads differ in size
            Packing.init(
                [.success(9), .failure(.init(code: 2))] as [Result<UInt8, Failure>],
                fixed: nil,
                [2, 0, 9, 1, 2, 0, 0, 0]
            ),
            // or have the same fixed size
            Packing.init(
                [.success(9), .failure(.init(code: 2))] as [Result<UInt32, Failure>],
                fixed: nil,
                [2, 0, 9, 0, 0, 0, 1, 2, 0, 0, 0]
            ),
        ]
    ) static func FixedSizes(_ packing: Packing) throws {
        #expect(packing.stated == packing.expected)
        #expect(packing.write() == packing.golden)
        #expect(try packing.read(packing.golden))
    }

    /// An inline array writes its elements with no count, or one zero byte when it has none,
    /// and states a fixed size whenever its elements do, so that a composite holding one keeps
    /// a fixed size of its own.
    @Test(
        arguments: [
            // fixed-size elements, packed
            Inline.init([7] as InlineArray<1, UInt32>, fixed: 4, [7, 0, 0, 0]),
            Inline.init([1, -2, 0x0102, 0] as InlineArray<4, Int16>, fixed: 8, [1, 0, 0xfe, 0xff, 2, 1, 0, 0]),
            // variable-size elements, each delimiting itself
            Inline.init(["ab", "", "é"] as InlineArray<3, String>, fixed: nil, [2, 0x61, 0x62, 0, 2, 0xc3, 0xa9]),
            // no elements: one zero byte, whatever the element
            Inline.init([] as InlineArray<0, Int64>, fixed: 1, [0]),
            Inline.init([] as InlineArray<0, String>, fixed: 1, [0]),
            Inline.init([[], []] as [InlineArray<0, String>], fixed: nil, [2, 0, 0]),
            // nested in an inline array, and in a composite, which then has a fixed size too
            Inline.init([[1, 2], [3, 4]] as InlineArray<2, InlineArray<2, UInt8>>, fixed: 4, [1, 2, 3, 4]),
            Inline.init(
                Ladder.init(prices: [0x0102, -1], side: .sell),
                fixed: 9,
                [2, 1, 0, 0, 0xff, 0xff, 0xff, 0xff, 0xff]
            ),
            Inline.init(
                [.init(prices: [1, 2], side: .buy)] as [Ladder],
                fixed: nil,
                [1, 1, 0, 0, 0, 2, 0, 0, 0, 1]
            ),
        ]
    ) static func InlineArrays(_ inline: Inline) throws {
        #expect(inline.stated == inline.expected)
        #expect(inline.write() == inline.golden)
        #expect(inline.size == inline.golden.count)
        #expect(try inline.reread(inline.golden) == inline.golden)
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

    /// A string, a substring and a contiguous value at the lengths where their ULEB128 length
    /// grows a byte, each with another byte behind it: the read must stop exactly where the
    /// value ends, whichever form its length took.
    @Test(
        arguments: [
            (127, [0x7f]),
            (128, [0x80, 0x01]),
            (16_383, [0xff, 0x7f]),
            (16_384, [0x80, 0x80, 0x01]),
        ] as [(Int, [UInt8])]
    ) static func Lengths(_ length: Int, _ prefix: [UInt8]) throws {
        let text: String = .init(repeating: "x", count: length)
        try Self.check(followed: text, prefix + .init(repeating: 0x78, count: length))
        try Self.check(followed: text[...], prefix + .init(repeating: 0x78, count: length))
        try Self.check(
            followed: Blob.init(bytes: .init(repeating: 9, count: length)),
            prefix + .init(repeating: 9, count: length)
        )
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

    /// Checks the bytes of `value` with one more byte behind them, and that a read of `value`
    /// leaves exactly that byte.
    private static func check<Value>(
        followed value: Value,
        _ expected: [UInt8]
    ) throws where Value: Transferable & Equatable {
        let bytes: [UInt8] = .init(capacity: value.transferSize + 1) {
            value.transfer(into: &$0)
            $0.append(0xa5)
        }
        #expect(bytes == expected + [0xa5])
        var input: TransferReader = .init(bytes.span.bytes)
        let decoded: Value = try .init(transferring: &input)
        let next: UInt8 = try input.take(UInt8.self)
        try input.finish()
        #expect(decoded == value)
        #expect(next == 0xa5)
    }
}
