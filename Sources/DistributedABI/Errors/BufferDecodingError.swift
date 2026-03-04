@frozen public enum BufferDecodingError<T>: Error {
    case size(Int, expected: Int? = nil)
}
extension BufferDecodingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .size(let actual, let expected?):
            "invalid buffer size for type '\(String.init(reflecting: T.self))' (\(actual) bytes), expected \(expected) bytes"
        case .size(let actual, nil):
            "invalid buffer size for type '\(String.init(reflecting: T.self))' (\(actual) bytes)"
        }
    }
}
