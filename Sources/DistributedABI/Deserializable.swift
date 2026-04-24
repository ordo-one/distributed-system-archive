/// Defines protocol used to deserialize distributed function call arguments or result type
/// **Important:** Protocol requirements is subject to change, API compatibility is not guaranteed at this moment of time
@available(*, deprecated) public protocol Deserializable: BufferDecodable {
    /// Creates a new instance by decoding from the given buffer.
    /// - Parameter from: the buffer to read data from
    init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) throws

    func _releaseBuffer()
}
@available(*, deprecated) extension Deserializable {
    // forwards compatibility with new API
    public static func decode(from input: inout BufferDecoder) throws -> Self {
        try input.bytes.withUnsafeBytes(self.init(fromSerializedBuffer:))
    }
}
@available(*, deprecated) extension Deserializable where Self: BitwiseCopyable {
    @inlinable static func loadUnaligned(
        from buffer: UnsafeRawBufferPointer
    ) throws(BufferDecodingError) -> Self {
        guard buffer.count == MemoryLayout<Self>.size else {
            throw .expected(.bytes(MemoryLayout<Self>.size), encountered: buffer.count)
        }
        return buffer.loadUnaligned(as: Self.self)
    }
}
@available(*, deprecated) extension Deserializable
    where Self: BinaryFloatingPoint & BitwiseCopyable {
    @inlinable public init(
        fromSerializedBuffer buffer: UnsafeRawBufferPointer
    ) throws(BufferDecodingError) {
        self = try .loadUnaligned(from: buffer)
    }

    public func _releaseBuffer() {}
}
@available(*, deprecated) extension Deserializable
    where Self: BinaryInteger & BitwiseCopyable {
    @inlinable public init(
        fromSerializedBuffer buffer: UnsafeRawBufferPointer
    ) throws(BufferDecodingError) {
        self = try .loadUnaligned(from: buffer)
    }

    public func _releaseBuffer() {}
}
