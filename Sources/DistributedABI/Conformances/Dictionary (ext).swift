extension Dictionary: BufferEncodable where Key: BufferEncodable, Value: BufferEncodable {
    @inlinable public func encode(into output: inout OutputRawSpan) {
        self.header.encode(into: &output)
        for (field, value): (Key, Value) in self {
            field.encode(into: &output)
            value.encode(into: &output)
        }
    }
    @inlinable public var encodedSize: Int {
        var size: Int = self.header.encodedSize
        for (field, value): (Key, Value) in self {
            size += field.encodedSize + value.encodedSize
        }
        return size
    }
}
extension Dictionary: BufferDecodable where Key: BufferDecodable, Value: BufferDecodable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        let header: CollectionHeader = try .decode(from: input, at: &index)
        //  Clamp the speculative reservation to the available bytes (see Array.decode).
        //  A key/value pair needs at least two bytes, so `remaining` is a safe bound.
        var fields: Self = .init(minimumCapacity: Swift.min(header.count, input.remaining(from: index)))
        for i: Int in 0 ..< header.count {
            let field: Key = try .decode(from: input, at: &index)
            let value: Value = try .decode(from: input, at: &index)
            switch fields.updateValue(value, forKey: field) {
            case nil:
                continue
            case _?:
                throw .arbitrary(DictionaryCollisionError<Key, Value>.init(position: i))
            }
        }
        return fields
    }
}
