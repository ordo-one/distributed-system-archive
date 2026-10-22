extension Set: Transferable where Element: Transferable {
    /// A set travels as an ``Swift/Array`` of its elements in iteration order; an element that
    /// repeats an earlier one is a ``TransferError/Kind/duplicate(_:)`` error.
    @inlinable public var transferSize: Int { self.elementsTransferSize }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        output.append(uleb128: UInt.init(self.count))
        for element: Element in self {
            output.append(framed: element)
        }
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        let count: Int = try input.takeCount(of: Element.self)
        self.init(minimumCapacity: count)
        for i: Int in 0 ..< count {
            guard case (inserted: true, _) = self.insert(try input.take(framed: Element.self)) else {
                throw .init(.duplicate(i))
            }
        }
    }
}
