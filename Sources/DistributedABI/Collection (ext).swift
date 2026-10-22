extension Collection where Element: Transferable {
    /// The size of the collection’s wire form, which ``transferElements(into:)`` writes.
    @inlinable var elementsTransferSize: Int {
        let count: Int = self.count
        let header: Int = ULEB128.size(UInt.init(count))
        if  let size: Int = Element.fixedTransferSize {
            return header + count * size
        } else {
            return self.reduce(header) { $0 + $1.framedTransferSize }
        }
    }

    /// A ULEB128 count, then the elements: packed when their type has a fixed size, and each
    /// preceded by its ULEB128 length otherwise.
    @inlinable func transferElements(into output: inout OutputRawSpan) {
        output.append(uleb128: UInt.init(self.count))
        for element: Element in self {
            output.append(framed: element)
        }
    }
}
