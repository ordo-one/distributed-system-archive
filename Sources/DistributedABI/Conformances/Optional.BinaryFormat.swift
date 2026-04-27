extension Optional {
    @frozen @usableFromInline enum BinaryFormat: UInt8, BufferEncodable, BufferDecodable {
        case none
        case some
    }
}
