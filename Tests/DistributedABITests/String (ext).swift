extension String: Fuzzable {
    /// Mostly a few scalars, sometimes enough of them that the length of the string takes two
    /// ULEB128 bytes, drawn from every length of UTF-8 sequence and from the combining marks.
    static func random(using random: inout SplitMix64, budget _: inout Int) -> Self {
        let count: Int = Int.random(in: 0 ..< 16, using: &random) == 0
            ? .random(in: 30 ... 80, using: &random)
            : .random(in: 0 ... 8, using: &random)
        var string: String = ""
        for _: Int in 0 ..< count {
            string.unicodeScalars.append(Self.scalar(using: &random))
        }
        return string
    }

    static func same(_ a: Self, _ b: Self) -> Bool { a.utf8.elementsEqual(b.utf8) }
}
extension String {
    private static func scalar(using random: inout SplitMix64) -> Unicode.Scalar {
        let ranges: [ClosedRange<UInt32>] = [
            0x00 ... 0x7f,
            0x80 ... 0x7ff,
            0x800 ... 0xd7ff,
            0xe000 ... 0xffff,
            0x1_0000 ... 0x10_ffff,
            0x300 ... 0x36f,
        ]
        let range: ClosedRange<UInt32> = ranges[.random(in: ranges.indices, using: &random)]
        // every range leaves out the surrogates, so every value is a scalar
        return Unicode.Scalar.init(UInt32.random(in: range, using: &random))!
    }
}
