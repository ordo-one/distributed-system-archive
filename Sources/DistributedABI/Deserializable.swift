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
    @available(
        *, deprecated, message: """
        modern deserialization API requires decoders to report the number of bytes consumed
        """
    ) public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        //  Legacy semantics: consume the whole remaining buffer.
        let start: Int = index
        let end: Int = input.byteCount
        index = end
        var result: Self? = nil
        var failure: (any Error)? = nil
        input.extracting(start ..< end).withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            do {
                result = try Self.init(fromSerializedBuffer: raw)
            } catch {
                failure = error
            }
        }
        if let failure: any Error { throw .arbitrary(failure) }
        return result.unsafelyUnwrapped
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
