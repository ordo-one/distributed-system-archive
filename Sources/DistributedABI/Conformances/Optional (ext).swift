@available(*, deprecated) extension Optional: Transferable where Wrapped: Transferable {}
extension Optional: BufferEncodable where Wrapped: BufferEncodable {
    @inlinable public func encode(into output: inout OutputRawSpan) {
        if  let self: Wrapped {
            BinaryFormat.some.encode(into: &output)
            self.encode(into: &output)
        } else {
            BinaryFormat.none.encode(into: &output)
        }
    }
    @inlinable public var encodedSize: Int {
        if  let self: Wrapped {
            return 1 + self.encodedSize
        } else {
            return 1
        }
    }
}
extension Optional: BufferDecodable where Wrapped: BufferDecodable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        let type: BinaryFormat = try .decode(from: input, at: &index)
        switch type {
        case .none:
            return nil
        case .some:
            return try Wrapped.decode(from: input, at: &index)
        }
    }
}
