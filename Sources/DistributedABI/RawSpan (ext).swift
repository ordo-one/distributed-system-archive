extension RawSpan {
    /// Refuses the first of these bytes that is `cases` or more, each the stored byte of a
    /// value with that many cases, with the ``TransferError/Kind/discriminant(_:)`` error a
    /// read of one value at a time reports for it. The bytes are scanned once for their
    /// largest, which vectorizes, and again only when one of them is refused.
    @inlinable func checkDiscriminants(below cases: Int) throws(TransferError) {
        let bytes: Span<UInt8> = .init(viewing: self)
        var largest: UInt8 = 0
        for i: Int in bytes.indices {
            largest = max(largest, bytes[i])
        }
        guard Int.init(largest) >= cases else {
            return
        }
        for i: Int in bytes.indices where Int.init(bytes[i]) >= cases {
            throw .init(.discriminant(.init(bytes[i])))
        }
    }
}
