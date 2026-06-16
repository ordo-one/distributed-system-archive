import DistributedABI

extension Roundtripping {
    struct VariableLengthBytes: Equatable {
        let bytes: ArraySlice<UInt8>
    }
}
extension Roundtripping.VariableLengthBytes {
    static func create(length: Int) -> Self {
        .init(bytes: (0 ..< length).map(UInt8.init(truncatingIfNeeded:))[...])
    }
}
extension Roundtripping.VariableLengthBytes: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        output.write(prefixing: self.bytes)
    }
}
extension Roundtripping.VariableLengthBytes: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        try input.parse { .init(bytes: $0) }
    }
}
