extension Array: Transferable where Element: Transferable {
    /// An array travels as a ULEB128 count, then its elements: packed when their type has a
    /// fixed size, and each preceded by its ULEB128 length otherwise.
    @inlinable public var transferSize: Int { self.span.elementsTransferSize }

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
