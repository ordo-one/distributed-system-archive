extension String {
    @frozen @usableFromInline enum BinaryFormat: UInt8, BufferEncodable, BufferDecodable {
        case compact = 0
        case long = 1
        case none = 2
    }
}
extension String.BinaryFormat {
    /// The maximum UTF-8 byte count encodable with the ``compact`` (null-terminated)
    /// format. Longer strings — or any containing a null byte — use ``long`` instead.
    @usableFromInline static var compactLimit: Int { 256 }
}
