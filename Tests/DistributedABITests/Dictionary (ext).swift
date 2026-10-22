extension Dictionary: Fuzzable where Key: Fuzzable, Value: Fuzzable {
    /// A dictionary travels in its iteration order, which another dictionary with the same
    /// entries need not share.
    static var shape: Fuzz.Shape { .entries(Key.shape, Value.shape) }

    static func random(using random: inout SplitMix64, budget: inout Int) -> Self {
        let count: Int = Fuzz.count(using: &random, budget: &budget)
        var dictionary: Self = .init(minimumCapacity: count)
        for _: Int in 0 ..< count {
            let key: Key = .random(using: &random, budget: &budget)
            dictionary[key] = .random(using: &random, budget: &budget)
        }
        return dictionary
    }

    static func same(_ a: Self, _ b: Self) -> Bool {
        a.count == b.count && a.allSatisfy {
            (key: Key, value: Value) in
            b[key].map { Value.same(value, $0) } ?? false
        }
    }
}
