extension Dictionary: BufferEncodable where
    Key: BufferEncodable,
    Value: BufferEncodable,
    Value.SerializationError == Key.SerializationError {
    @inlinable public func encode(
        to output: inout BufferEncoder
    ) throws(Value.SerializationError) {
        self.header.encode(to: &output)

        for (field, value): (Key, Value) in self {
            try field.encode(to: &output)
            try value.encode(to: &output)
        }
    }
}
extension Dictionary: BufferDecodable where Key: BufferDecodable, Value: BufferDecodable {
    @inlinable public static func decode(
        from input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        let header: CollectionHeader = try .decode(from: &input)
        var fields: Self = .init(minimumCapacity: header.count)
        for i: Int in 0 ..< header.count {
            let field: Key
            let value: Value
            do {
                field = try .decode(from: &input)
                value = try .decode(from: &input)
            } catch let error as BufferDecodingError {
                throw error
            } catch {
                throw .arbitrary(error)
            }
            switch fields.updateValue(value, forKey: field) {
            case nil:
                continue
            case _?:
                // i wish that we could store information about the offending key-value pair
                // here, but that would run afoul of Swift concurrency checking. additionally,
                // it would make the conditional conformance a mouthful to spell (and
                // understand), even if that were to compile, which it won’t
                throw .arbitrary(DictionaryCollisionError<Key, Value>.init(position: i))
            }
        }

        return fields
    }
}
