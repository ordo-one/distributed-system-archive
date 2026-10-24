extension ContiguousArray: Transferable where Element: Transferable {
    /// A contiguous array travels exactly as an ``Swift/Array`` with the same elements.
    @inlinable public var transferSize: Int {
        // elements of a fixed size need only the count, as an array’s do
        if  let size: Int = Element.fixedTransferSize {
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
    /// Elements stored as their transfer bytes are read with one copy into new storage, and
    /// others one at a time; either way, a count the bytes remaining cannot hold is refused
    /// before anything is reserved.
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        guard case let (size, cases)? = Element.bitwiseTransfer else {
            try self.init(transferringElements: &input)
            return
        }
        let count: Int = try input.takeCount(of: Element.self)
        if  count == 0 {
            self.init()
            return
        }
        if  let cases: Int {
            // checked where they lie, before any is taken, so that a byte of no case is refused
            // with the reader where a read of one element at a time leaves it
            try input.checkDiscriminants(count, below: cases)
        }
        // cannot overflow, since that many elements fit in the bytes remaining
        let bytes: RawSpan = input.take(holding: count &* size)
        if  _isConcrete(Element.self) {
            // specialized for the element type, reserving inline with the storage type known,
            // as a read of one element at a time does: the initializer below allocates through
            // a function of the standard library that looks the storage type up at run time
            self.init()
            self.append(addingCapacity: count) { $0.append(bitwise: bytes, count: count) }
        } else {
            // generic, the initializer that hands out the uninitialized storage, which looks up
            // one generic type where reserving, or the span-based initializer, looks up several
            self = unsafe .init(unsafeUninitializedCapacity: count) {
                (buffer: inout UnsafeMutableBufferPointer<Element>, initialized: inout Int) in
                bytes.withUnsafeBytes {
                    unsafe UnsafeMutableRawBufferPointer.init(buffer).copyMemory(from: $0)
                }
                initialized = count
            }
        }
    }
}
