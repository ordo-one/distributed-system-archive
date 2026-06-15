@available(*, deprecated) extension Double: TriviallyCopyable, Transferable {}
extension Double: BufferEncodable {
    @inlinable public func encode(into output: inout OutputRawSpan) {
        self.bitPattern.encode(into: &output)
    }
    @inlinable public var encodedSize: Int { MemoryLayout<UInt64>.size }
}
extension Double: BufferDecodable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        .init(bitPattern: try .decode(from: input, at: &index))
    }
}
