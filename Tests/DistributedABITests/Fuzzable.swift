import DistributedABI

/// A transferable type whose values the fuzz tests can draw at random.
protocol Fuzzable: Transferable {
    /// The layout of the wire form, as far as putting it in canonical order needs it.
    static var shape: Fuzz.Shape { get }

    /// A random value. A collection spends one unit of `budget` on each of its elements, and
    /// has none once the budget is spent.
    static func random(using random: inout SplitMix64, budget: inout Int) -> Self

    /// Whether two values are the same: equal, with the same bytes for a string, and with the
    /// same bits for a floating-point number, so that a NaN is the same as itself.
    static func same(_ a: Self, _ b: Self) -> Bool
}
extension Fuzzable {
    static var shape: Fuzz.Shape { Self.transferLayout.map { Fuzz.Shape.fixed($0.size) } ?? .opaque }
}
extension Fuzzable where Self: Equatable {
    static func same(_ a: Self, _ b: Self) -> Bool { a == b }
}
extension Fuzzable where Self: FixedWidthInteger {
    /// An edge value half the time, and any value of the type otherwise.
    static func random(using random: inout SplitMix64, budget _: inout Int) -> Self {
        switch Int.random(in: 0 ..< 8, using: &random) {
        case 0: .min
        case 1: .max
        case 2: .zero
        case 3: .zero &- 1
        default: .random(in: .min ... .max, using: &random)
        }
    }
}
