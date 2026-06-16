@frozen public struct BufferDecodingError: Error {
    @usableFromInline let type: BufferDecodingErrorType
    @inlinable init(type: BufferDecodingErrorType) {
        self.type = type
    }
}
extension BufferDecodingError {
    @inlinable static func expected(
        _ what: BufferDecodingError.Expectation,
        encountered: Int
    ) -> Self {
        .init(type: .expected(what, encountered: encountered))
    }
    @inlinable public static func arbitrary(_ error: consuming any Error) -> Self {
        .init(type: .arbitrary(error))
    }
}
extension BufferDecodingError: CustomStringConvertible {
    public var description: String {
        switch self.type {
        case .arbitrary(let error):
            "buffer decoding error (\(error))"
        case .expected(.bytes(let expected), encountered: let actual):
            "invalid buffer size (\(actual) bytes), expected \(expected) bytes"
        case .expected(let what, encountered: _):
            "buffer decoding error, expected \(what)"
        }
    }
}
