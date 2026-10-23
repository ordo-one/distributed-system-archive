extension ContiguousArray: Transferable where Element: Transferable {
    /// A contiguous array travels exactly as an ``Swift/Array`` with the same elements.
    @inlinable public var transferSize: Int {
        // elements of a fixed size need only the count, as an array’s do
        if  let size: Int = Element.fixedTransferSize {
            return ULEB128.size(UInt.init(self.count)) + self.count * size
        }
        return self.span.arrayTransferSize
    }

    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(uleb128: UInt.init(self.count))
        for element: Element in self {
            output.append(element: element)
        }
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        try self.init(transferringElements: &input)
    }
}
