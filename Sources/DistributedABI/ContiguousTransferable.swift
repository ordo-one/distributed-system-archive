/// A value whose memory already is its wire form, such as a serialized message or an
/// identifier.
///
/// A conformer lends its bytes and opens from a copy of them; the protocol supplies the three
/// ``Transferable`` requirements from those two, so the transport sizes the frame from the byte
/// count and moves the value with one memcpy. A type whose size varies writes its ULEB128
/// length before its bytes, so that it delimits itself wherever it travels; a type that states
/// a ``TransferLayout/fixed(size:)`` layout writes its bytes alone.
public protocol ContiguousTransferable: Transferable {
    /// Lends the value’s bytes, unchanged, for the duration of `body`.
    ///
    /// This is a closure rather than a property so that a type which builds its bytes on demand
    /// can conform.
    func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result

    /// Opens a value over a copy of `transferBytes`, after whatever validation the type needs.
    init(transferBytes: RawSpan) throws(TransferError)
}
extension ContiguousTransferable {
    /// The size of the type’s layout when it states one, without lending the bytes; otherwise
    /// the byte count of the lent bytes and of the ULEB128 length in front of them.
    @inlinable public var transferSize: Int {
        if  let size: Int = Self.transferLayout?.size {
            return size
        }
        return self.withTransferBytes { ULEB128.size(UInt.init($0.byteCount)) + $0.byteCount }
    }

    @inlinable public func transfer(into output: inout TransferWriter) {
        self.withTransferBytes {
            if  case nil = Self.transferLayout {
                output.append(prefixed: $0)
            } else {
                output.append(bytes: $0)
            }
        }
    }

    /// Reads the size of the type’s ``Transferable/transferLayout`` when it states one, and
    /// otherwise a ULEB128 length and that many bytes.
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        if  let size: Int = Self.transferLayout?.size {
            try self.init(transferBytes: try input.take(size))
        } else {
            try self.init(transferBytes: try input.takeContiguous())
        }
    }
}
