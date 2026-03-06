extension String: Serializable {
    public func withUnsafeBytesSerialization<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        try utf8CString.withUnsafeBufferPointer {
            try body(.init(start: .init($0.baseAddress), count: $0.count - 1))
        }
    }
}
extension String: Deserializable {
    public init(fromSerializedBuffer buffer: UnsafeRawBufferPointer) {
        self = String(unsafeUninitializedCapacity: buffer.count) {
            _ = $0.initialize(from: buffer)
            return buffer.count
        }
    }

    public func _releaseBuffer() {}
}
extension String: Transferable {}
