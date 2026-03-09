/// Defines protocol used to deserialize distributed function call arguments or result type
/// **Important:** Protocol requirements is subject to change, API compatibility is not guaranteed at this moment of time
public protocol Deserializable {
    /// Creates a new instance by decoding from the given buffer.
    /// - Parameter from: the buffer to read data from
    init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) throws

    func _releaseBuffer()
}
extension Deserializable where Self: BitwiseCopyable {
    static func loadUnaligned(from buffer: UnsafeRawBufferPointer) throws(BufferDecodingError<Self>) -> Self {
        guard buffer.count == MemoryLayout<Self>.size else {
            throw BufferDecodingError<Self>.size(buffer.count, expected: MemoryLayout<Self>.size)
        }
        return buffer.loadUnaligned(as: Self.self)
    }
}
extension Deserializable where Self: BinaryFloatingPoint & BitwiseCopyable {
    public init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) throws(BufferDecodingError<Self>) {
        self = try .loadUnaligned(from: buffer)
    }

    public func _releaseBuffer() {}
}
extension Deserializable where Self: BinaryInteger & BitwiseCopyable {
    public init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) throws(BufferDecodingError<Self>) {
        self = try .loadUnaligned(from: buffer)
    }

    public func _releaseBuffer() {}
}
