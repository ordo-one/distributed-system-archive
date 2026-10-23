extension Array: Transferable where Element: Transferable {
    /// An array travels as a ULEB128 count, then its elements one after another, each of
    /// which delimits itself.
    @inlinable public var transferSize: Int {
        // elements of a fixed size need only the count: asking an array bridged from an
        // `NSArray` for its span would first copy its elements into contiguous storage
        if  let size: Int = Element.fixedTransferSize {
            return ULEB128.size(UInt.init(self.count)) + self.count * size
        }
        return self.span.arrayTransferSize
    }

    /// Elements stored as their transfer bytes, which ``Transferable/isBitwiseTransferable``
    /// states, are written with one copy of their storage, and others one at a time.
    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(uleb128: UInt.init(self.count))
        if  self.count != 0, case _? = Element.bitwiseTransferStride {
            output.append(bitwise: self.span)
            return
        }
        for element: Element in self {
            output.append(element: element)
        }
    }
    /// Elements stored as their transfer bytes are read with one copy into new storage, and
    /// others one at a time; either way, a count the bytes remaining cannot hold is refused
    /// before anything is reserved.
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        guard
        let size: Int = Element.bitwiseTransferStride else {
            try self.init(transferringElements: &input)
            return
        }
        let count: Int = try input.takeCount(of: Element.self)
        if  count == 0 {
            self.init()
            return
        }
        // cannot overflow, since that many elements fit in the bytes remaining
        let bytes: RawSpan = try input.take(count &* size)
        // the initializer that hands out the uninitialized storage, which allocates in one call
        // with one lookup of the storage type, where the span-based one looks up several
        // generic types when the element type is not concrete
        self = unsafe .init(unsafeUninitializedCapacity: count) {
            (buffer: inout UnsafeMutableBufferPointer<Element>, initialized: inout Int) in
            bytes.withUnsafeBytes { unsafe UnsafeMutableRawBufferPointer.init(buffer).copyMemory(from: $0) }
            initialized = count
        }
    }
}
