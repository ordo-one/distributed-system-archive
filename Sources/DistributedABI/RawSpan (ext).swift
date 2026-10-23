extension RawSpan {
    /// The offset of the first of these bytes that is `cases` or more, each the stored byte of
    /// a value with that many discriminants, or nil when there is none. The bytes are scanned
    /// once for their largest, which vectorizes, and searched byte by byte only when that is
    /// out of range.
    @inlinable func firstDiscriminant(notBelow cases: Int) -> Int? {
        let bytes: Span<UInt8> = .init(viewing: self)
        var largest: UInt8 = 0
        for i: Int in bytes.indices {
            largest = max(largest, bytes[i])
        }
        guard Int.init(largest) >= cases else {
            return nil
        }
        for i: Int in bytes.indices where Int.init(bytes[i]) >= cases {
            return i
        }
        return nil
    }
}
extension TransferReader {
    /// Checks the next `count` bytes, which the bytes remaining hold, against a number of
    /// discriminants, without consuming them. At the first byte that is `cases` or more, it
    /// consumes the bytes up to and including that one, as a read of one value at a time
    /// would, and refuses it with the ``TransferError/Kind/discriminant(_:)`` error that read
    /// reports, so that the reader stands where the read of one value at a time leaves it.
    @inlinable mutating func checkDiscriminants(_ count: Int, below cases: Int) throws(TransferError) {
        // cannot overflow, since `count` fits in the bytes remaining
        let next: RawSpan = self.bytes.extracting(self.index ..< self.index &+ count)
        guard
        let offset: Int = next.firstDiscriminant(notBelow: cases) else {
            return
        }
        let byte: UInt8 = next.load(fromByteOffset: offset, as: UInt8.self)
        self.index &+= offset &+ 1
        throw .init(.discriminant(.init(byte)))
    }
}
