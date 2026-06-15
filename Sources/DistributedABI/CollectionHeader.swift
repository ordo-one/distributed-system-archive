@frozen @usableFromInline struct CollectionHeader {
    @usableFromInline let count: Int
    @inlinable init(count: Int) {
        self.count = count
    }
}
extension CollectionHeader: BufferEncodable {
    @inlinable func encode(into output: inout OutputRawSpan) {
        //  `UInt8.max` is reserved as the marker for the extended (full-width count)
        //  header, so a single-byte count can only go up to `UInt8.max - 1`.
        if  self.count < Int.init(UInt8.max) {
            output.append(UInt8.init(self.count))
        } else {
            output.append(UInt8.max)
            self.count.encode(into: &output)
        }
    }
    @inlinable var encodedSize: Int {
        self.count < Int.init(UInt8.max) ? 1 : 1 + MemoryLayout<Int>.size
    }
}
extension CollectionHeader: BufferDecodable {
    @inlinable static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        let first: UInt8 = try input.parseByte(at: &index)
        if  first == .max {
            let count: Int = try .decode(from: input, at: &index)
            //  A negative count is never valid and would trap the `0 ..< count`
            //  loops that consume collection elements; reject it up front.
            guard count >= 0 else {
                throw input.expected(.bytes(0), at: index)
            }
            return .init(count: count)
        } else {
            return .init(count: Int.init(first))
        }
    }
}
