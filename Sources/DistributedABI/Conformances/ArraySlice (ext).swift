extension ArraySlice: Transferable where Element: Transferable {
    /// A slice travels exactly as an ``Swift/Array`` with the same elements.
    @inlinable public var transferSize: Int { self.elementsTransferSize }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        self.transferElements(into: &output)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        try self.init(transferringElements: &input)
    }
}
