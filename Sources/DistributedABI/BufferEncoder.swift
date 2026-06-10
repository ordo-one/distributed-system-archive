@frozen public struct BufferEncoder: ~Copyable, Sendable {
    @usableFromInline var bytes: [UInt8]

    /// Create an output with a pre-allocated destination buffer. The buffer
    /// does *not* need to be empty, and existing data will not be cleared.
    ///
    /// >   Note:
    ///     The slice's contents are copied into the encoder's internal storage
    ///     (`[UInt8]`), unless the slice spans an entire array buffer that is
    ///     uniquely referenced, in which case the conversion is free.
    @inlinable public init(preallocated bytes: ArraySlice<UInt8>) {
        self.bytes = .init(bytes)
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
        consuming get { self.bytes[...] }
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
