extension Set: BufferEncodable where Element: BufferEncodable {}
extension Set: BufferDecodable where Element: BufferDecodable {
    @inlinable public static func decode(
        from input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        let header: CollectionHeader = try .decode(from: &input)
        var values: Self = []
        //  Clamp the speculative reservation to the available bytes (see Array.decode).
        values.reserveCapacity(Swift.min(header.count, input.remaining))
        for i: Int in 0 ..< header.count {
            let value: Element
            do {
                value = try .decode(from: &input)
            } catch let error as BufferDecodingError {
                throw error
            } catch {
                throw .arbitrary(error)
            }

            guard case (inserted: true, _) = values.insert(value) else {
                throw .arbitrary(SetCollisionError<Element>.init(position: i))
            }
        }

        return values
    }
}
