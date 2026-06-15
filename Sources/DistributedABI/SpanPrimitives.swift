//  The single low-level read/write vocabulary the codec is built on.
//
//  Decoding reads through a borrowed `RawSpan` + an `Int` cursor; encoding writes
//  through a borrowed `OutputRawSpan`. The SAME witnesses serve both the
//  zero-copy path (a span over foreign memory — a SwiftNIO `ByteBuffer`, an LMDB
//  mmap / `MDB_RESERVE` page) and the owned path (a span borrowed from a
//  caller's `[UInt8]` via `withUnsafeBytes`, with no copy).
//
//  Crucially, NO type stores a span: the span is always a function parameter, so
//  none of this needs `~Escapable`, `@_lifetime`, or the experimental `Lifetimes`
//  feature. (A struct that *stores* a `RawSpan` would force all three.)

extension RawSpan {
    /// The number of bytes after `index`. Because every encoded element occupies
    /// at least one byte, this is a safe upper bound on the element count a
    /// (possibly hostile) length header can require, and is used to clamp
    /// speculative `reserveCapacity` calls.
    @inlinable func remaining(from index: Int) -> Int {
        Swift.max(0, self.byteCount - index)
    }

    @inlinable func expected(
        _ expectation: BufferDecodingError.Expectation,
        at index: Int
    ) -> BufferDecodingError {
        .expected(expectation, encountered: self.byteCount - index)
    }

    /// Consumes and returns a single byte, advancing `index`.
    @inlinable func parseByte(at index: inout Int) throws(BufferDecodingError) -> UInt8 {
        guard index >= 0, index < self.byteCount else {
            throw self.expected(.bytes(1), at: index)
        }
        //  A `UInt8` has alignment 1, so any offset is aligned — `unsafeLoad`
        //  (not `unsafeLoadUnaligned`) is correct and clearer here.
        let byte: UInt8 = self.unsafeLoad(fromByteOffset: index, as: UInt8.self)
        index &+= 1
        return byte
    }

    /// Consumes `MemoryLayout<T>.size` bytes and returns them as a little-endian `T`.
    @inlinable func parseLittleEndian<T>(
        _: T.Type,
        at index: inout Int
    ) throws(BufferDecodingError) -> T where T: FixedWidthInteger & BitwiseCopyable {
        let size: Int = MemoryLayout<T>.size
        let start: Int = index
        //  `size <= byteCount - start` (rather than `start + size <= byteCount`) is
        //  overflow-safe: `start >= 0` and `byteCount >= 0`, so the subtraction can
        //  never wrap. A wrapping `start &+ size` near `Int.max` could otherwise
        //  bypass the check and admit an out-of-bounds read.
        guard start >= 0, size <= self.byteCount - start else {
            throw self.expected(.bytes(size), at: index)
        }
        let raw: T = self.unsafeLoadUnaligned(fromByteOffset: start, as: T.self)
        index = start &+ size
        return T(littleEndian: raw)
    }

    /// Consumes `size` bytes and yields a borrowed subspan over exactly that
    /// region — no copy. The subspan must not escape the closure.
    @inlinable func parse<T>(
        size: Int,
        at index: inout Int,
        with yield: (RawSpan) -> T
    ) throws(BufferDecodingError) -> T {
        let start: Int = index
        //  Overflow-safe bound (see parseLittleEndian): with `size, start >= 0` the
        //  subtraction cannot wrap, whereas `start &+ size` near `Int.max` could.
        guard size >= 0, start >= 0, size <= self.byteCount - start else {
            throw self.expected(.bytes(size), at: index)
        }
        index = start &+ size
        return yield(self.extracting(start ..< start &+ size))
    }

    /// Advances past the next occurrence of `terminator`, yielding a borrowed
    /// subspan over the bytes skipped (excluding the terminator). Scans the raw
    /// memory directly: `firstIndex(of:)` lowers to a vectorized `memchr`.
    @inlinable func parse<T>(
        through terminator: UInt8,
        at index: inout Int,
        with yield: (RawSpan) -> T
    ) throws(BufferDecodingError) -> T {
        let start: Int = index
        let count: Int = self.byteCount
        guard start >= 0, start <= count else {
            throw self.expected(.byte(terminator), at: index)
        }
        //  Slices of `UnsafeRawBufferPointer` keep the base index space, so the
        //  returned offset is absolute and needs no rebasing.
        let match: Int? = self.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int? in
            buffer[start ..< count].firstIndex(of: terminator)
        }
        guard let match: Int else {
            index = count
            throw .expected(.byte(terminator), encountered: 0)
        }
        index = match &+ 1
        return yield(self.extracting(start ..< match))
    }
}

extension OutputRawSpan {
    /// Bulk-copies a contiguous run of bytes (e.g. the UTF-8 of a string) into the
    /// region. There is no safe `OutputRawSpan` bulk-append entry point, so this
    /// goes through the contained unsafe escape, kept in-library. It preconditions
    /// against the reserved capacity BEFORE the copy: an under-sized reservation (a
    /// bug in an `encodedSize` estimate) fails loudly rather than corrupting
    /// adjacent memory.
    @inlinable mutating func append(copying source: UnsafeRawBufferPointer) {
        guard let base: UnsafeRawPointer = source.baseAddress, source.count > 0 else {
            return
        }
        let n: Int = source.count
        self.withUnsafeMutableBytes {
            (dest: UnsafeMutableRawBufferPointer, initializedCount: inout Int) in
            precondition(
                n <= dest.count - initializedCount,
                "encode wrote past the reserved region (encodedSize under-estimate)"
            )
            dest.baseAddress!.advanced(by: initializedCount)
                .copyMemory(from: base, byteCount: n)
            initializedCount += n
        }
    }
}
