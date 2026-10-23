extension OutputSpan where Element: Transferable {
    /// Initializes the next `count` elements by copying `bytes`, the transfer bytes of exactly
    /// that many elements of a type with a ``Transferable/bitwiseTransferStride``, whose
    /// storage is those bytes.
    @_lifetime(self: copy self)
    @inlinable @inline(always) mutating func append(bitwise bytes: RawSpan, count: Int) {
        unsafe self.withUnsafeMutableBufferPointer {
            (buffer: UnsafeMutableBufferPointer<Element>, initialized: inout Int) in
            precondition(count <= buffer.count &- initialized, "OutputSpan capacity overflow")
            let target: UnsafeMutableRawBufferPointer = unsafe .init(
                UnsafeMutableBufferPointer<Element>.init(
                    rebasing: buffer[initialized ..< initialized &+ count]
                )
            )
            bytes.withUnsafeBytes {
                assert($0.count == target.count, "the bytes of \(count) elements")
                unsafe target.copyMemory(from: $0)
            }
            initialized &+= count
        }
    }
}
