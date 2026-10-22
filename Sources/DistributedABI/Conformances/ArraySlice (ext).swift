extension ArraySlice: Transferable where Element: Transferable {
    /// A slice travels exactly as an ``Swift/Array`` with the same elements.
    @inlinable public var transferSize: Int { self.elementsTransferSize }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        output.append(uleb128: UInt.init(self.count))
        for element: Element in self {
            output.append(framed: element)
        }
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        try self.init(transferringElements: &input)
    }
}
