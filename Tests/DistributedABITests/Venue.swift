import DistributedABI

/// An enum with a two-byte raw value.
enum Venue: UInt16, Equatable, Transferable {
    case primary = 0x0102
    case dark = 0xfffe
}
