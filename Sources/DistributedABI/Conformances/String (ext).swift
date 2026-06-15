@available(*, deprecated) extension String: Transferable {}
extension String: BufferEncodable {
    @inlinable public func encode(into output: inout OutputRawSpan) {
        self[...].encode(into: &output)
    }
    @inlinable public var encodedSize: Int { self[...].encodedSize }
}
extension String: BufferDecodable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        let format: BinaryFormat = try .decode(from: input, at: &index)
        switch format {
        case .compact:
            return try .decode(compact: input, at: &index)
        case .long:
            return try .decode(long: input, at: &index)
        case .none:
            return ""
        }
    }
}
extension String {
    /// Parses a null-terminated string.
    @inlinable static func decode(
        compact input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        try input.parse(through: 0x00, at: &index) { (bytes: RawSpan) -> String in
            bytes.withUnsafeBytes { .init(decoding: $0, as: Unicode.UTF8.self) }
        }
    }

    /// Parses a length-prefixed string.
    @inlinable static func decode(
        long input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        let low: UInt32 = try .decode(from: input, at: &index)
        let high: UInt8 = try .decode(from: input, at: &index)
        //  Compute the 40-bit length through `UInt64` so the `>> 32` is well-defined
        //  on 32-bit platforms (the bytes are identical on 64-bit).
        let size: Int = Int.init(UInt64.init(high) << 32 | UInt64.init(low))
        return try input.parse(size: size, at: &index) { (bytes: RawSpan) -> String in
            bytes.withUnsafeBytes { .init(decoding: $0, as: Unicode.UTF8.self) }
        }
    }
}
