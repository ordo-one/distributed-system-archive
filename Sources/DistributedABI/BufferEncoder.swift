@frozen public struct BufferEncoder: ~Copyable, Sendable {
    @usableFromInline var bytes: [UInt8]

    /// Create an output that takes ownership of a pre-allocated destination buffer,
    /// without copying. The buffer does *not* need to be empty, and existing data
    /// will not be cleared. This is the zero-copy entry point: pass a buffer whose
    /// capacity you want to reuse (e.g. one reclaimed from a previous encoder via
    /// ``storage`` after ``Swift/Array/removeAll(keepingCapacity:)``), and the
    /// encoder appends in place with no reallocation while the buffer stays unique.
    @inlinable public init(preallocated bytes: consuming [UInt8]) {
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
        consuming get { self.bytes[...] }
    }
    /// Consumes the encoder and returns its backing `[UInt8]` buffer directly,
    /// with no copy. The returned array retains its full capacity, so it can be
    /// cleared (`removeAll(keepingCapacity:)`) and handed back to
    /// ``init(preallocated:)`` to reuse the allocation across many encodes.
    @inlinable public var storage: [UInt8] {
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
