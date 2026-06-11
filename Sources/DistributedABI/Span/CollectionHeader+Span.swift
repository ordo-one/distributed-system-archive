//  MARK: - CollectionHeader (zero-copy decode)

extension CollectionHeader {
    /// Decodes a collection header from a ``SpanDecoder``. This mirrors the
    /// `BufferDecoder` path in `CollectionHeader.swift` byte-for-byte (1 byte if
    /// the count is < 255, otherwise `0xFF` followed by a little-endian `Int`),
    /// including the DoS hardening that rejects a negative count up front. The
    /// `BufferDecoder` overload in `CollectionHeader.swift` is left untouched.
    @inlinable static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        let first: UInt8 = try .decode(from: &input)
        if  first == .max {
            let count: Int = try .decode(from: &input)
            //  A negative count is never valid and would trap the `0 ..< count`
            //  loops that consume collection elements; reject it up front.
            guard count >= 0 else {
                throw input.expected(.bytes(0))
            }
            return .init(count: count)
        } else {
            return .init(count: Int.init(first))
        }
    }
}
