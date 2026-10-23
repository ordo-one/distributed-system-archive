extension ArraySlice: Transferable where Element: Transferable {
    /// A slice travels exactly as an ``Swift/Array`` with the same elements.
    @inlinable public var transferSize: Int {
        // elements of a fixed size need only the count, as an array’s do
        if  let size: Int = Element.fixedTransferSize {
            return ULEB128.size(UInt.init(self.count)) + self.count * size
        }
        return self.span.arrayTransferSize
    }

    /// Elements stored as their transfer bytes, which ``Transferable/isBitwiseTransferable``
    /// states, are written with one copy of their storage, and others one at a time.
    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(uleb128: UInt.init(self.count))
        if  self.count != 0, case _? = Element.bitwiseTransfer {
            output.append(bitwise: self.span)
            return
        }
        for element: Element in self {
            output.append(element: element)
        }
    }
    /// Reads an ``Swift/Array`` of the same elements, exactly as an array reads itself, and
    /// slices it whole, sharing its storage.
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self = try Array<Element>.init(transferring: &input)[...]
    }
}
