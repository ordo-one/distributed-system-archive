extension Optional {
    @usableFromInline enum BinaryFormat: UInt8, BufferEncodable, BufferDecodable {
        case none
        case some
    }
}
