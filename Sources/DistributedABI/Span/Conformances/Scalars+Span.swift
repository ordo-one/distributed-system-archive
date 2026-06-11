//  MARK: - Scalar conformances

extension Bool: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        switch try input.parse() {
        case 0:
            return false
        case 1:
            return true
        case let code:
            throw .arbitrary(BufferDiscriminationError<UInt8, Self>.init(code: code))
        }
    }
}

extension Int8: SpanDecodable {}
extension Int16: SpanDecodable {}
extension Int32: SpanDecodable {}
extension Int64: SpanDecodable {}
extension Int: SpanDecodable {}
extension UInt8: SpanDecodable {}
extension UInt16: SpanDecodable {}
extension UInt32: SpanDecodable {}
extension UInt64: SpanDecodable {}
extension UInt: SpanDecodable {}

extension Double: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        .init(bitPattern: try .decode(from: &input))
    }
}
extension Float: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        .init(bitPattern: try .decode(from: &input))
    }
}
