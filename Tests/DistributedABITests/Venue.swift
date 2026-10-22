import DistributedABI

/// An enum with a two-byte raw value.
enum Venue: UInt16, Equatable, Transferable {
    case primary = 0x0102
    case dark = 0xfffe
}
extension Venue: Fuzzable {
    static func random(using random: inout SplitMix64, budget _: inout Int) -> Self {
        Bool.random(using: &random) ? .primary : .dark
    }
}
