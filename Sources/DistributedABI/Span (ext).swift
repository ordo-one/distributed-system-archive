extension Span where Element: Transferable {
    /// The size of these elements as the wire form of a collection: a ULEB128 count, then the
    /// elements one after another, each of which delimits itself.
    ///
    /// Indexing the span lends each element where it lies. Where this body is specialized for
    /// the element type, as it is in a client that names the type, the optimizer can size the
    /// lent element without copying it: a send of class-backed messages measures no retain or
    /// release. The unspecialized generic body may still copy each element to ask for its
    /// size and destroy the copy after, which retains and releases an element that holds a
    /// reference. A loop over the array itself copies each element unless the optimizer can
    /// show the copy is not needed, which depends on how the element lends its bytes.
    @inlinable var elementsTransferSize: Int {
        let header: Int = ULEB128.size(UInt.init(self.count))
        if  let size: Int = Element.fixedTransferSize {
            return header + self.count * size
        }
        var size: Int = header
        for i: Int in self.indices {
            size += self[i].transferSize
        }
        return size
    }
}
