/// Defines protocol used to deserialize distributed function call arguments or result type
/// **Important:** Protocol requirements is subject to change, API compatibility is not guaranteed at this moment of time
public protocol Deserializable {
    /// Creates a new instance by decoding from the given buffer.
    /// - Parameter from: the buffer to read data from
    init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) throws

    func _releaseBuffer()
}
