@frozen @usableFromInline enum BufferDecodingErrorType {
    case arbitrary(any Error)
    /// The `encountered` field is the number of bytes available in the input.
    case expected(BufferDecodingError.Expectation, encountered: Int)
}
