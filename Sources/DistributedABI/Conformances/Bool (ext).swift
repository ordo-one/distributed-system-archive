extension Bool: Serializable {
    public func withUnsafeBytesSerialization<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        try Swift.withUnsafeBytes(of: self) {
            try body(UnsafeRawBufferPointer($0))
        }
    }
}
extension Bool: Deserializable {
    public init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) throws(BufferDecodingError<Self>) {
        guard buffer.count == MemoryLayout<Self>.size else {
            throw BufferDecodingError<Self>.size(buffer.count, expected: MemoryLayout<Self>.size)
        }
        self = buffer.loadUnaligned(as: Self.self)
    }

    public func _releaseBuffer() {}
}
extension Bool: Transferable {}
