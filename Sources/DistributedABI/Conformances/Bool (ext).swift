@available(*, deprecated) extension Bool: Transferable {}
extension Bool: BufferEncodable {
    @inlinable public func encode(to output: inout BufferEncoder) {
        output.append(self ? 1 : 0)
    }
}
extension Bool: BufferDecodable {
    @inlinable public static func decode(
        from input: inout BufferDecoder
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
