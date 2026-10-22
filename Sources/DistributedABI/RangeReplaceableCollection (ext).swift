extension RangeReplaceableCollection where Element: Transferable {
    /// Reads what `transferElements(into:)` writes.
    @inlinable init(transferringElements input: inout TransferReader) throws(TransferError) {
        let count: Int = try input.takeCount(of: Element.self)
        self.init()
        self.reserveCapacity(count)
        for _: Int in 0 ..< count {
            self.append(try input.take(framed: Element.self))
        }
    }
}
