extension Collection where Element: Transferable {
    /// The size of the collection’s wire form: a ULEB128 count, then the elements, packed when
    /// their type has a fixed size, and each preceded by its ULEB128 length otherwise. An array
    /// or a slice sizes its elements through its span instead, which lends each one in place;
    /// a set has no span, and every loop over it copies each element out of its storage. The
    /// conformances write the elements in a loop of their own, because a loop over a generic
    /// collection retains and releases every element, even when specialized.
    @inlinable var elementsTransferSize: Int {
        let count: Int = self.count
        let header: Int = ULEB128.size(UInt.init(count))
        if  let size: Int = Element.fixedTransferSize {
            return header + count * size
        } else {
            return self.reduce(header) { $0 + $1.framedTransferSize }
        }
    }
}
