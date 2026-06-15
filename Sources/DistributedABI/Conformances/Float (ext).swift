@available(*, deprecated) extension Float: TriviallyCopyable, Transferable {}
extension Float: BufferEncodable {
    @inlinable public func encode(into output: inout OutputRawSpan) {
        self.bitPattern.encode(into: &output)
    }
    @inlinable public var encodedSize: Int { MemoryLayout<UInt32>.size }
}
extension Float: BufferDecodable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        .init(bitPattern: try .decode(from: input, at: &index))
    }
}
