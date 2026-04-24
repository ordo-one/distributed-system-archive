@available(*, deprecated) extension String: Transferable {}
extension String: BufferEncodable {
    @inlinable public func encode(to output: inout BufferEncoder) {
        self[...].encode(to: &output)
    }
}
extension String: BufferDecodable {
    public static func decode(
        from input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        let format: BinaryFormat = try .decode(from: &input)
        switch format {
        case .compact:
            return try .decode(compact: &input)
        case .long:
            return try .decode(long: &input)
        case .none:
            return ""
        }
    }
}
extension String {
    /// Parses a null-terminated string.
    @usableFromInline static func decode(
        compact input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        try input.parse(through: 0x00) { .init(decoding: $0, as: Unicode.UTF8.self) }
    }

    /// Parses a length-prefixed string.
    @usableFromInline static func decode(
        long input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        let low: UInt32 = try .decode(from: &input)
        let high: UInt8 = try .decode(from: &input)
        let size: Int = Int.init(high) << 32 | Int.init(low)
        return try input.parse(size: size) { .init(decoding: $0, as: Unicode.UTF8.self) }
    }
}
