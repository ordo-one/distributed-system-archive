@frozen @usableFromInline enum CollectionHeaderError: Error {
    case count(Int)
}
extension CollectionHeaderError: CustomStringConvertible {
    @usableFromInline var description: String {
        switch self {
        case .count(let count):
            "invalid collection count (\(count))"
        }
    }
}
