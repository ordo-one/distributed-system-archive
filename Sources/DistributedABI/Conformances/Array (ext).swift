extension Array: Transferable where Element: Transferable {
    /// An array travels as a ULEB128 count, then its elements: packed when their type has a
    /// fixed size, and each preceded by its ULEB128 length otherwise.
    @inlinable public var transferSize: Int { self.elementsTransferSize }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        self.transferElements(into: &output)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        try self.init(transferringElements: &input)
    }
}
