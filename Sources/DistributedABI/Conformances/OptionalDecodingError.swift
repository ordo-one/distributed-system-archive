@frozen @usableFromInline enum OptionalDecodingError<T>: Error {
    case invalidDiscriminant(UInt8)
}
extension OptionalDecodingError: CustomStringConvertible {
    @usableFromInline var description: String {
        switch self {
        case .invalidDiscriminant(let code):
            "invalid discriminant ([0] = \(code)) while decoding Optional<\(String.init(reflecting: T.self))>"
        }
    }
}
