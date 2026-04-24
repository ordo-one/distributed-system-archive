extension Bool: Serializable {
    public func withUnsafeBytesSerialization<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        try Swift.withUnsafeBytes(of: self, body)
    }
}
extension Bool: Deserializable {
    @inlinable public init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) throws(BufferDecodingError<Self>) {
        self = try .loadUnaligned(from: buffer)
    }

    public func _releaseBuffer() {}
}
extension Bool: Transferable {}
