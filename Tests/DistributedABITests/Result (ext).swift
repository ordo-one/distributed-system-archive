extension Result: Fuzzable where Success: Fuzzable, Failure: Fuzzable {
    static var shape: Fuzz.Shape { .cases([Success.shape, Failure.shape]) }

    static func random(using random: inout SplitMix64, budget: inout Int) -> Self {
        Bool.random(using: &random)
            ? .success(.random(using: &random, budget: &budget))
            : .failure(.random(using: &random, budget: &budget))
    }

    static func same(_ a: Self, _ b: Self) -> Bool {
        switch (a, b) {
        case (.success(let a), .success(let b)): Success.same(a, b)
        case (.failure(let a), .failure(let b)): Failure.same(a, b)
        default: false
        }
    }
}
