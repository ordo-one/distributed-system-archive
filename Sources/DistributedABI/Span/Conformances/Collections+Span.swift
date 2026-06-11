//  MARK: - Collections

extension Array: SpanDecodable where Element: SpanDecodable {}
extension ArraySlice: SpanDecodable where Element: SpanDecodable {}

extension Set: SpanDecodable where Element: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
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

extension Dictionary: SpanDecodable where Key: SpanDecodable, Value: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        let header: CollectionHeader = try .decode(from: &input)
        //  Clamp the speculative reservation to the available bytes (see Array.decode).
        //  A key/value pair needs at least two bytes, so `remaining` is a safe bound.
        var fields: Self = .init(minimumCapacity: Swift.min(header.count, input.remaining))
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
                throw .arbitrary(DictionaryCollisionError<Key, Value>.init(position: i))
            }
        }

        return fields
    }
}
