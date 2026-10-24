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
        case .truncated(needed: let needed, remaining: let remaining):
            "expected \(needed) byte(s), but \(remaining) remain"
        case .trailingBytes(remaining: let remaining):
            "expected end of input, but \(remaining) byte(s) remain"
        case .excessiveCount(let count, remaining: let remaining):
            "count or length \(count) exceeds the \(remaining) byte(s) remaining"
        case .malformedULEB128(remaining: let remaining):
            "malformed ULEB128 number, with \(remaining) byte(s) remaining"
        case .invalidDiscriminant(let code):
            "invalid discriminant (\(code))"
        case .duplicate(at: let position):
            "duplicate element at position [\(position)]"
        case .payload(let error):
            "\(error)"
        }
    }
}
