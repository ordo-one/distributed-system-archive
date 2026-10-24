extension Span where Element: Transferable {
    /// The number of bytes these elements take in the wire form of an array: a ULEB128 count,
    /// then the elements one after another, each of which delimits itself. The count is
    /// included, so this is the ``Transferable/transferSize`` of an ``Swift/Array`` with the
    /// same elements, and a collection of one’s own that writes an array’s wire form can return
    /// it from its own `transferSize`, over a span of its elements. It is not the size of an
    /// inline array, which writes no count. Elements whose type states a layout are sized from the count
    /// alone, without visiting any of them.
    ///
    /// Indexing the span lends each element where it lies. Where this body is specialized for
    /// the element type, as it is in a client that names the type, the optimizer can size the
    /// lent element without copying it: a send of class-backed messages measures no retain or
    /// release. The unspecialized generic body may still copy each element to ask for its
    /// size and destroy the copy after, which retains and releases an element that holds a
    /// reference. A loop over the array itself copies each element unless the optimizer can
    /// show the copy is not needed, which depends on how the element lends its bytes.
    @inlinable public var arrayTransferSize: Int {
        let header: Int = ULEB128.size(UInt.init(self.count))
        if  let size: Int = Element.transferLayout?.size {
            return header + self.count * size
        }
        var size: Int = header
        for i: Int in self.indices {
            size += self[i].transferSize
        }
        return size
    }
}
