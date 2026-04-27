@frozen @usableFromInline struct CollectionHeader {
    @usableFromInline let count: Int
    @inlinable init(count: Int) {
        self.count = count
    }
}
extension CollectionHeader: BufferEncodable {
    @inlinable func encode(to output: inout BufferEncoder) {
        let count: Int = self.count
        let first: UInt8

        if  count < 255 {
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
            return .init(count: try .decode(from: &input))
        } else {
            return .init(count: Int.init(first))
        }
    }
}
