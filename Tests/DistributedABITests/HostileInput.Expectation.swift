import DistributedABI

extension HostileInput {
    /// A ``TransferError/Kind`` with the payload reduced to its presence, so cases compare.
    enum Expectation: Equatable, Sendable {
        case expected(Int, encountered: Int)
        case count(Int, remaining: Int)
        case discriminant(UInt64)
        case duplicate(Int)
        case payload
    }
}
extension HostileInput.Expectation {
    init(_ kind: TransferError.Kind) {
        switch kind {
        case .expected(let expected, encountered: let encountered):
            self = .expected(expected, encountered: encountered)
        case .count(let count, remaining: let remaining):
            self = .count(count, remaining: remaining)
        case .discriminant(let code):
            self = .discriminant(code)
        case .duplicate(let position):
            self = .duplicate(position)
        case .payload:
            self = .payload
        }
    }
}
