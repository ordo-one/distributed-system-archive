extension ArraySlice: Transferable where Element: Transferable {
    /// A slice travels exactly as an ``Swift/Array`` with the same elements.
    @inlinable public var transferSize: Int {
        // elements of a fixed size need only the count, as an array’s do
        if  let size: Int = Element.transferLayout?.size {
            return ULEB128.size(UInt.init(self.count)) + self.count * size
        }
        return self.span.arrayTransferSize
    }

    /// The count, then the elements through ``TransferWriter/append(elements:)``, which writes
    /// elements stored as their transfer bytes with one copy of their storage, and others one
    /// at a time; through the witness table, its loop over the span costs less than a loop over
    /// the array. Specialized for an element type moved one at a time, the elements go through
    /// a loop over the array itself instead, which the optimizer lends each element from where
    /// it lies, where a loop over the span copies an element that holds a reference across its
    /// write.
    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(uleb128: UInt.init(self.count))
        if  _isConcrete(Element.self), case nil = Element.bitwiseTransfer {
            for element: Element in self {
                output.append(element: element)
            }
        } else if self.count != 0 {
            output.append(elements: self.span)
        }
    }
    /// Reads an ``Swift/Array`` of the same elements, exactly as an array reads itself, and
    /// slices it whole, sharing its storage.
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self = try Array<Element>.init(transferring: &input)[...]
    }
}
