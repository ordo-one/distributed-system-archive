extension Set: BufferEncodable where Element: BufferEncodable {}
extension Set: BufferDecodable where Element: BufferDecodable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        let header: CollectionHeader = try .decode(from: input, at: &index)
        var values: Self = []
        //  Clamp the speculative reservation to the available bytes (see Array.decode).
        values.reserveCapacity(Swift.min(header.count, input.remaining(from: index)))
        for i: Int in 0 ..< header.count {
            let value: Element = try .decode(from: input, at: &index)
            guard case (inserted: true, _) = values.insert(value) else {
                throw .arbitrary(SetCollisionError<Element>.init(position: i))
            }
        }
        return values
    }
}
