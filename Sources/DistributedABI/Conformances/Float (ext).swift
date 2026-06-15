@available(*, deprecated) extension Float: TriviallyCopyable, Transferable {}
extension Float: BufferEncodable {
    @inlinable public func encode(to output: inout BufferEncoder) {
        self.bitPattern.encode(to: &output)
    }
}
extension Float: BufferDecodable {
    @inlinable public static func decode(
        from input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        .init(bitPattern: try .decode(from: &input))
    }
}
