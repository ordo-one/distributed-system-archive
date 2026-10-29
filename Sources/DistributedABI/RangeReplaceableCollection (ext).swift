extension RangeReplaceableCollection where Element: Transferable {
    /// Reads a collection in the wire form of an ``Swift/Array``: a ULEB128 count, through
    /// ``TransferReader/readCount(of:)``, then that many elements one after another, each
    /// through ``TransferReader/read(_:)``, appended in the order they were written. A
    /// range-replaceable collection of one’s own can read itself with this from its
    /// ``Transferable/init(transferring:)``, and then reads exactly the bytes an array with the
    /// same elements writes.
    ///
    /// The count is refused before any room is reserved when the bytes remaining could not
    /// hold that many elements.
    @inlinable public init(
        transferringElements input: inout TransferReader
    ) throws(TransferError) {
        let count: Int = try input.readCount(of: Element.self)
        self.init()
        self.reserveCapacity(count)
        for _: Int in 0 ..< count {
            self.append(try input.read(Element.self))
        }
    }
}
