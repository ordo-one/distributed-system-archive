import DistributedABI

/// An enum with a signed 128-bit raw value, whose refusal must report every bit.
enum WideSigned: Int128, Equatable, Transferable {
    case one = 1
}
