extension RangeReplaceableCollection where Element: Transferable {
    /// Reads a ULEB128 count, then that many elements, one after another, through
    /// ``TransferReader/takeElement(_:)``.
    @inlinable init(transferringElements input: inout TransferReader) throws(TransferError) {
        let count: Int = try input.takeCount(of: Element.self)
        self.init()
        self.reserveCapacity(count)
        for _: Int in 0 ..< count {
            self.append(try input.takeElement(Element.self))
        }
    }
}
