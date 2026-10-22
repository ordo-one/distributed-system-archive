/// The one error every decode throws.
///
/// The library refuses malformed or hostile input with one of the structural kinds, and a
/// conformer that refuses its own bytes wraps its error in ``payload(_:)``, which the transport
/// can read back unchanged.
@frozen public struct TransferError: Error {
    public let kind: Kind

    @inlinable public init(_ kind: Kind) {
        self.kind = kind
    }
}
extension TransferError {
    /// Wraps a conformer’s own error.
    @inlinable public static func payload(_ error: any Error) -> Self { .init(.payload(error)) }
}
extension TransferError: CustomStringConvertible {
    public var description: String {
        switch self.kind {
        case .expected(let expected, encountered: let encountered):
            if  expected == 0 {
                "expected end of input, but \(encountered) byte(s) remain"
            } else {
                "expected \(expected) byte(s), but \(encountered) remain"
            }
        case .count(let count, remaining: let remaining):
            if  count < 0 {
                "malformed ULEB128 number, with \(remaining) byte(s) remaining"
            } else {
                "count or length \(count) exceeds the \(remaining) byte(s) remaining"
            }
        case .discriminant(let code):
            "invalid discriminant (\(code))"
        case .duplicate(let position):
            "duplicate element at position [\(position)]"
        case .payload(let error):
            "\(error)"
        }
    }
}
