@frozen @usableFromInline struct CollectionHeader {
    @usableFromInline let count: Int
    @inlinable init(count: Int) {
        self.count = count
    }
}
extension CollectionHeader {
    @inlinable var hint: Int {
        self.count + (self.count < 0xff ? 1 : 1 + MemoryLayout<Int>.size)
    }
}
extension CollectionHeader: BufferEncodable {
    @inlinable func encode(to output: inout BufferEncoder) {
        let count: Int = self.count
        let first: UInt8

        //  `UInt8.max` is reserved as the marker for the extended (full-width count)
        //  header, so a single-byte count can only go up to `UInt8.max - 1`.
        if  count < .init(UInt8.max) {
            first = .init(count)
            first.encode(to: &output)
        } else {
            first = .max
            first.encode(to: &output)
            count.encode(to: &output)
        }
    }
}
extension CollectionHeader: BufferDecodable {
    @inlinable static func decode(
        from input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        let first: UInt8 = try .decode(from: &input)
        if  first == .max {
            let count: Int = try .decode(from: &input)
            //  A negative count is never valid and would trap the `0 ..< count`
            //  loops that consume collection elements; reject it up front.
            guard count >= 0 else {
                throw .arbitrary(CollectionHeaderError.count(count))
            }
            return .init(count: count)
        } else {
            return .init(count: Int.init(first))
        }
    }
}
