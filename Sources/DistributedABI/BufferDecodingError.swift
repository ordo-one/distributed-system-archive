@frozen public enum BufferDecodingError: Error {
    case arbitrary(any Error)
    /// The `encountered` field is the number of bytes available in the input.
    case expected(Expectation, encountered: Int)
}
extension BufferDecodingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .arbitrary(let error):
            "buffer decoding error (\(error)))"
        case .expected(.bytes(let expected), encountered: let actual):
            "invalid buffer size (\(actual) bytes), expected \(expected) bytes"
        case .expected(let what, encountered: _):
            "buffer decoding error, expected \(what)"
        }
    }
}
