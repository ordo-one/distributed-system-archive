extension Optional: Fuzzable where Wrapped: Fuzzable {
    static var shape: Fuzz.Shape { .cases([nil, Wrapped.shape]) }

    static func random(using random: inout SplitMix64, budget: inout Int) -> Self {
        Int.random(in: 0 ..< 4, using: &random) == 0
            ? nil
            : Wrapped.random(using: &random, budget: &budget)
    }

    static func same(_ a: Self, _ b: Self) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case (let a?, let b?): Wrapped.same(a, b)
        default: false
        }
    }
}
