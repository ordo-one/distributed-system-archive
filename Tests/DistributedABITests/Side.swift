import DistributedABI

/// An enum with a signed one-byte raw value, as the transport’s predicate types have.
enum Side: Int8, Equatable, Transferable {
    case buy = 1
    case sell = -1
}
extension Side: Fuzzable {
    static func random(using random: inout SplitMix64, budget _: inout Int) -> Self {
        Bool.random(using: &random) ? .buy : .sell
    }
}
