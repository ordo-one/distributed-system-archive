extension Float: Fuzzable {
    /// A special value a quarter of the time, and any bit pattern otherwise, which reaches
    /// NaN payloads and subnormal numbers.
    static func random(using random: inout SplitMix64, budget _: inout Int) -> Self {
        if  case 0 = Int.random(in: 0 ..< 4, using: &random) {
            let special: [Self] = [
                .nan,
                -.nan,
                .signalingNaN,
                .infinity,
                -.infinity,
                0,
                -0.0,
                .leastNonzeroMagnitude,
                .greatestFiniteMagnitude,
                1,
            ]
            return special[.random(in: special.indices, using: &random)]
        } else {
            return .init(bitPattern: .random(in: .min ... .max, using: &random) as UInt32)
        }
    }

    static func same(_ a: Self, _ b: Self) -> Bool { a.bitPattern == b.bitPattern }
}
