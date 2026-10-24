extension Set: Transferable where Element: Transferable {
    /// A set travels as an ``Swift/Array`` of its elements in iteration order; an element that
    /// repeats an earlier one is a ``TransferError/Kind/duplicate(at:)`` error.
    @inlinable public var transferSize: Int {
        let header: Int = ULEB128.size(self.count)
        if  let size: Int = Element.transferLayout?.size {
            return header + self.count * size
        }
        // a loop of the set’s own, as the write is: a loop over a generic collection costs
        // more, and no loop over a set borrows its elements, so each one is copied out of the
        // set’s storage and released after
        var size: Int = header
        for element: Element in self {
            size += element.transferSize
        }
        return size
    }

    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(uleb128: self.count)
        for element: Element in self {
            output.append(element: element)
        }
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        let count: Int = try input.readCount(of: Element.self)
        self.init(minimumCapacity: count)
        for i: Int in 0 ..< count {
            guard case (inserted: true, _) = self.insert(try input.read(Element.self)) else {
                throw .init(.duplicate(at: i))
            }
        }
    }
}
