import DistributedABI

extension HostileInput {
    /// A ``TransferError/Kind`` with the payload reduced to its presence, so cases compare.
    enum Expectation: Equatable, Sendable {
        case truncated(needed: Int, remaining: Int)
        case trailingBytes(remaining: Int)
        case excessiveCount(Int, remaining: Int)
        case malformedULEB128(remaining: Int)
        case invalidDiscriminant(UInt128)
        case duplicate(at: Int)
        case payload
    }
}
extension HostileInput.Expectation {
    init(_ kind: TransferError.Kind) {
        switch kind {
        case .truncated(needed: let needed, remaining: let remaining):
            self = .truncated(needed: needed, remaining: remaining)
        case .trailingBytes(remaining: let remaining):
            self = .trailingBytes(remaining: remaining)
        case .excessiveCount(let count, remaining: let remaining):
            self = .excessiveCount(count, remaining: remaining)
        case .malformedULEB128(remaining: let remaining):
            self = .malformedULEB128(remaining: remaining)
        case .invalidDiscriminant(let code):
            self = .invalidDiscriminant(code)
        case .duplicate(at: let position):
            self = .duplicate(at: position)
        case .payload:
            self = .payload
        }
    }
}
