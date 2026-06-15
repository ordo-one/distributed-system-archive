@available(*, deprecated) extension Optional: Transferable where Wrapped: Transferable {}
extension Optional: BufferEncodable where Wrapped: BufferEncodable {
    @inlinable public func encode(
        to output: inout BufferEncoder
    ) throws(Wrapped.SerializationError) {
        if  let self: Wrapped {
            BinaryFormat.some.encode(to: &output)
            try self.encode(to: &output)
        } else {
            BinaryFormat.none.encode(to: &output)
        }
    }
}
extension Optional: BufferDecodable where Wrapped: BufferDecodable {
    @inlinable public static func decode(
        from input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        let type: BinaryFormat = try .decode(from: &input)
        switch type {
        case .none:
            return nil

        case .some:
            do {
                return try Wrapped.decode(from: &input)
            } catch let error as BufferDecodingError {
                throw error
            } catch {
                throw .arbitrary(error)
            }
        }
    }
}
