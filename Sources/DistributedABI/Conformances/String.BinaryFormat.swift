extension String {
    @frozen @usableFromInline enum BinaryFormat: UInt8, BufferEncodable, BufferDecodable {
        case compact = 0
        case long = 1
        case none = 2
    }
}
