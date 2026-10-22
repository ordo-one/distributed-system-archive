extension Set: Fuzzable where Element: Fuzzable {
    /// A set travels in its iteration order, which another set with the same elements need not
    /// share.
    static var shape: Fuzz.Shape { .elements(Element.shape, ordered: false) }

    static func random(using random: inout SplitMix64, budget: inout Int) -> Self {
        let count: Int = Fuzz.count(using: &random, budget: &budget)
        var set: Self = .init(minimumCapacity: count)
        for _: Int in 0 ..< count {
            set.insert(.random(using: &random, budget: &budget))
        }
        return set
    }
}
