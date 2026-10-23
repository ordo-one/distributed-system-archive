extension Array: Transferable where Element: Transferable {
    /// An array travels as a ULEB128 count, then its elements one after another, each of
    /// which delimits itself.
    @inlinable public var transferSize: Int {
        // elements of a fixed size need only the count: asking an array bridged from an
        // `NSArray` for its span would first copy its elements into contiguous storage
        if  let size: Int = Element.fixedTransferSize {
            return ULEB128.size(UInt.init(self.count)) + self.count * size
        }
        return self.span.elementsTransferSize
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
