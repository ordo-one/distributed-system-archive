@frozen public struct BufferEncoder: ~Copyable, Sendable {
    @usableFromInline var bytes: ArraySlice<UInt8>

    /// Create an output with a pre-allocated destination buffer. The buffer
    /// does *not* need to be empty, and existing data will not be cleared.
    @inlinable public init(preallocated bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
    }

    /// Create an empty output, reserving enough space for the specified
    /// number of bytes in the destination buffer.
    @inlinable public init(capacity: Int) {
        self.bytes = .init()
        self.bytes.reserveCapacity(capacity)
    }
}
extension BufferEncoder {
    @inlinable public var output: ArraySlice<UInt8> {
        consuming get { self.bytes }
    }
}
extension BufferEncoder {
    /// Reserves another `bytes` worth of capacity in the output destination, in addition to the
    /// bytes already present.
    @inlinable mutating func reserve(another bytes: Int) {
        self.bytes.reserveCapacity(self.bytes.count + bytes)
    }

    /// Appends a single byte to the output destination.
    @inlinable mutating func append(_ byte: UInt8) {
        self.bytes.append(byte)
    }
    /// Appends a sequence of bytes to the output destination.
    @inlinable mutating func append(_ bytes: some Sequence<UInt8>) {
        self.bytes.append(contentsOf: bytes)
    }
}

