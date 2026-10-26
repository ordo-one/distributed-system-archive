extension Bool: Fuzzable {
    static func random(using random: inout SplitMix64, budget _: inout Int) -> Self {
        .random(using: &random)
    }
}
