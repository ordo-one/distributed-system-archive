extension Bool: Transferable {
    /// A `Bool` travels as one byte, 0 or 1; any other byte is a discriminant error.
    @inlinable public static var fixedTransferSize: Int? { 1 }
    @inlinable public var transferSize: Int { 1 }

    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(self ? 1 : 0)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        switch try input.take(UInt8.self) {
        case 0: self = false
        case 1: self = true
        case let code: throw .init(.discriminant(.init(code)))
        }
    }
}
