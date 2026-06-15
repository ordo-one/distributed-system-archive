@available(*, deprecated) extension Bool: Transferable {}
extension Bool: BufferEncodable {
    @inlinable public func encode(into output: inout OutputRawSpan) {
        output.append(self ? 1 : 0)
    }
    @inlinable public var encodedSize: Int { 1 }
}
extension Bool: BufferDecodable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        switch try input.parseByte(at: &index) {
        case 0:
            return false
        case 1:
            return true
        case let code:
            throw .arbitrary(BufferDiscriminationError<UInt8, Self>.init(code: code))
        }
    }
}
