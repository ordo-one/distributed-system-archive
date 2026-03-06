extension Optional: Serializable where Wrapped: Serializable {
    public func withUnsafeBytesSerialization<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        switch self {
        case .none:
            return try withUnsafeTemporaryAllocation(byteCount: 1, alignment: 1) { buffer in
                buffer[0] = 0
                return try body(.init(buffer))
            }
        case .some(let wrapped):
            return try wrapped.withUnsafeBytesSerialization { bytes in
                try withUnsafeTemporaryAllocation(byteCount: 1 + bytes.count, alignment: 1) { buffer in
                    buffer[0] = 1
                    if bytes.count > 0 {
                        buffer.baseAddress!.advanced(by: 1).copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
                    }
                    return try body(.init(buffer))
                }
            }
        }
    }
}

extension Optional: Deserializable where Wrapped: Deserializable {
    public init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) throws {
        if buffer.count == 0 {
            throw BufferDecodingError<Self>.size(0)
        }
        if buffer[0] == 0 {
            if buffer.count != 1 {
                throw BufferDecodingError<Self>.size(buffer.count, expected: 1)
            }
            self = .none
        } else {
            let firstByte = buffer.baseAddress!.advanced(by: 1)
            self = .some(try Wrapped(fromSerializedBuffer: UnsafeRawBufferPointer(start: firstByte, count: buffer.count - 1)))
        }
    }

    public func _releaseBuffer() {
        if case let .some(value) = self {
            value._releaseBuffer()
        }
    }
}

extension Optional: Transferable where Wrapped: Transferable {}
