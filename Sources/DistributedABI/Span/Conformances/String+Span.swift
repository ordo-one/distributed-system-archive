//  MARK: - String / Substring

extension String: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        //  `String.BinaryFormat`: .compact = 0, .long = 1, .none = 2.
        let format: UInt8 = try input.parse()
        switch format {
        case 0:     // .compact — null-terminated UTF-8
            return try input.parse(through: 0x00) {
                (region: RawSpan) -> String in
                region.withUnsafeBytes { String(decoding: $0, as: Unicode.UTF8.self) }
            }
        case 1:     // .long — length-prefixed UTF-8
            let low: UInt32 = try .decode(from: &input)
            let high: UInt8 = try .decode(from: &input)
            // shift on `UInt64` so the `<< 32` is well-defined on 32-bit too
            let size: Int = .init(UInt64(high) << 32 | UInt64(low))
            return try input.parse(size: size) {
                (region: RawSpan) -> String in
                region.withUnsafeBytes { String(decoding: $0, as: Unicode.UTF8.self) }
            }
        case 2:     // .none — empty
            return ""
        case let code:
            //  Invalid `String.BinaryFormat` discriminant. The `ArraySlice` path
            //  surfaces this through the format enum's `RawRepresentable` decode as a
            //  `BufferDiscriminationError`; mirror that exactly.
            throw .arbitrary(
                BufferDiscriminationError<UInt8, String.BinaryFormat>.init(code: code)
            )
        }
    }
}

extension Substring: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        try String.decode(from: &input)[...]
    }
}
