extension Optional {
    @usableFromInline enum ABI {
        @inlinable static var none: UInt8 { 0 }
        @inlinable static var some: UInt8 { 1 }
    }
}
extension Optional: Serializable where Wrapped: Serializable {
    public func withUnsafeBytesSerialization<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        guard
        let self: Wrapped = self else {
            let none: UInt8 = ABI.none
            return try withUnsafeBytes(of: none, body)
        }
        return try self.withUnsafeBytesSerialization { (buffer: UnsafeRawBufferPointer) in
            let size: Int = buffer.count
            if  size <= 0 {
                let some: UInt8 = ABI.some
                return try withUnsafeBytes(of: some, body)
            }
            return try withUnsafeTemporaryAllocation(byteCount: size + 1, alignment: 1) {
                let first: Int = $0.startIndex
                let start: Int = $0.index(after: first)

                $0[first] = ABI.some
                let slice: UnsafeMutableRawBufferPointer = .init(rebasing: $0[start...])
                ;   slice.copyMemory(from: buffer)
                return try body(UnsafeRawBufferPointer.init($0))
            }
        }
    }
}

extension Optional: Deserializable where Wrapped: Deserializable {
    @inlinable public init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) throws {
        guard let first: Int = buffer.indices.first else {
            throw BufferDecodingError<Self>.size(0)
        }
        let start: Int = buffer.index(after: first)
        switch buffer[first] {
        case ABI.none:
            guard start == buffer.endIndex else {
                throw BufferDecodingError<Self>.size(buffer.count, expected: 1)
            }
            self = nil

        case ABI.some:
            let slice: UnsafeRawBufferPointer = .init(rebasing: buffer[start...])
            self = try Wrapped.init(fromSerializedBuffer: slice)

        case let invalid:
            throw OptionalDecodingError<Wrapped>.invalidDiscriminant(invalid)
        }
    }

    public func _releaseBuffer() {
        if case let .some(value) = self {
            value._releaseBuffer()
        }
    }
}

extension Optional: Transferable where Wrapped: Transferable {}
