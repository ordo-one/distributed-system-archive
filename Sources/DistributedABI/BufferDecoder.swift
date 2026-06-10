/// A type for managing buffer parsing state. Most users of this library
/// should not need to interact with it directly.
@frozen public struct BufferDecoder: ~Copyable, Sendable {
    @usableFromInline let bytes: ArraySlice<UInt8>
    @usableFromInline var index: Int

    /// Creates a parsing input view over the given `source` data,
    /// and initializes its `index` to the start index of the `source`.
    @inlinable public init(_ source: ArraySlice<UInt8>) {
        self.bytes = source
        self.index = self.bytes.startIndex
    }
}
extension BufferDecoder {
    /// Consumes and returns a single byte from this parsing input.
    @inlinable mutating func next() -> UInt8? {
        guard self.index < self.bytes.endIndex else {
            return nil
        }
        defer {
            self.bytes.formIndex(after: &self.index)
        }

        return self.bytes[self.index]
    }
    /// Consumes and returns a single byte from this parsing input.
    @inlinable mutating func parse() throws(BufferDecodingError) -> UInt8 {
        guard let byte: UInt8 = self.next() else {
            throw self.expected(.bytes(1))
        }
        return byte
    }
}
extension BufferDecoder {
    @inlinable public mutating func parse<T>(
        size: Int,
        with yield: (ArraySlice<UInt8>) -> T
    ) throws(BufferDecodingError) -> T {
        let start: Int = self.index

        guard
        let end: Int = self.bytes.index(
            self.index,
            offsetBy: size,
            limitedBy: self.bytes.endIndex
        ) else {
            throw self.expected(.bytes(size))
        }

        self.index = end
        return yield(self.bytes[start ..< end])
    }

    /// Advances the current index until encountering the specified `byte`.
    /// After this method returns, `index` points to the byte after
    /// the matched byte.
    ///
    /// -   Returns:
    ///         A range covering the bytes skipped. The upper-bound of
    ///         the range points to the matched byte.
    @discardableResult
    @inlinable public mutating func parse<T>(
        through byte: UInt8,
        with yield: (ArraySlice<UInt8>) -> T
    ) throws(BufferDecodingError) -> T {
        let start: Int = self.index
        let lower: Int = self.bytes.startIndex
        // scan over the unchecked buffer rather than the slice itself, to
        // avoid per-byte bounds (and exclusivity) checks
        let match: Int? = self.bytes.withUnsafeBufferPointer {
            (buffer: UnsafeBufferPointer<UInt8>) -> Int? in

            var i: Int = start - lower
            while i < buffer.count {
                if  buffer[i] == byte {
                    return i + lower
                }
                i += 1
            }
            return nil
        }

        guard
        let match: Int else {
            self.index = self.bytes.endIndex
            throw .expected(.byte(byte), encountered: 0)
        }

        self.index = match + 1
        return yield(self.bytes[start ..< match])
    }

    /// Asserts that all available bytes have been consumed, throwing an error otherwise.
    /// It is not necessary to call this, but it is often helpful to do so.
    @inlinable public func finish() throws(BufferDecodingError) {
        guard self.index == self.bytes.endIndex else {
            throw self.expected(.end)
        }
    }
}
extension BufferDecoder {
    /// The number of bytes remaining to be consumed from the input. Because every
    /// encoded element occupies at least one byte on the wire, this is a safe upper
    /// bound on the number of elements a (possibly hostile) length header can require,
    /// and should be used to clamp speculative `reserveCapacity` calls.
    @inlinable public var remaining: Int {
        self.bytes.distance(from: self.index, to: self.bytes.endIndex)
    }
}
extension BufferDecoder {
    /// Creates an ``InputError`` with appropriate context for the specified expectation.
    @inlinable func expected(
        _ expectation: BufferDecodingError.Expectation
    ) -> BufferDecodingError {
        .expected(
            expectation,
            encountered: self.bytes.distance(from: self.index, to: self.bytes.endIndex)
        )
    }
}
