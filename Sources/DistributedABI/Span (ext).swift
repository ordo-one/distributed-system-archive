extension Span where Element: Transferable {
    /// The size of these elements as the wire form of a collection: a ULEB128 count, then the
    /// elements, packed when their type has a fixed size, and each preceded by its ULEB128
    /// length otherwise.
    ///
    /// The span lends each element in place, so sizing an element neither copies nor retains
    /// it. A loop over the elements themselves copies each one unless the optimizer can show
    /// the copy is not needed, which depends on how the element lends its bytes.
    @inlinable var elementsTransferSize: Int {
        let header: Int = ULEB128.size(UInt.init(self.count))
        if  let size: Int = Element.fixedTransferSize {
            return header + self.count * size
        }
        var size: Int = header
        for i: Int in self.indices {
            size += self[i].framedTransferSize
        }
        return size
    }
}
