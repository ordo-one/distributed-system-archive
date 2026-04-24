@available(*, deprecated) extension Double: TriviallyCopyable, Transferable {}
extension Double: BufferEncodable {
    @inlinable public func encode(to output: inout BufferEncoder) {
        self.bitPattern.encode(to: &output)
    }
}
extension Double: BufferDecodable {
    @inlinable public static func decode(
        from input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        .init(bitPattern: try .decode(from: &input))
    }
}
