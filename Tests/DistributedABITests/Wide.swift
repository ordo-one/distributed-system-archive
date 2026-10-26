import DistributedABI

/// An enum with an unsigned 128-bit raw value, whose refusal must report every bit.
enum Wide: UInt128, Equatable, Transferable {
    case low = 1
    case high = 0x8000_0000_0000_0000_0000_0000_0000_0000
}
