//  ZERO-COPY decode entry point (ser-0xff / blindspotbounty review asks).
//
//  `BufferDecoder` stores an `ArraySlice<UInt8>`, so decoding from a SwiftNIO
//  `ByteBuffer`, an LMDB mmap, or any `UnsafeRawBufferPointer` first requires
//  copying the whole message into an `Array`. `SpanDecoder` is the same parsing
//  state machine over a borrowed `RawSpan` + `Int` cursor, so it can decode
//  directly out of foreign memory with no copy.
//
//  It decodes the SAME wire format as `BufferDecoder` (little-endian fixed-width
//  integers, format-byte + null-terminated compact strings, format-byte
//  optionals, `CollectionHeader`-prefixed collections), so a `received`
//  `RawSpan` produced from a `ByteBuffer.withUnsafeReadableBytes { RawSpan(_unsafeBytes:) }`
//  decodes byte-for-byte identically to today's `Array`-backed path.
//
//  Requires `-enable-experimental-feature Lifetimes` on THIS target only; clients
//  building against the resilient `OrdoDistributedABI` dylib do NOT need the flag
//  (the lifetime annotations are an implementation detail of the module). Verified
//  to build with `-enable-library-evolution`.
//
//  `SpanDecoder` is purely additive and decode-only: it never mutates
//  `BufferDecoder` and reuses the existing wire-format vocabulary types
//  (`CollectionHeader`, `String.BinaryFormat`, `Optional.BinaryFormat`,
//  `BufferDecodingError`, `BufferDiscriminationError`, `Set`/`Dictionary`
//  collision errors) without disturbing the `ArraySlice` decode paths.

/// A zero-copy parsing-state view over raw memory. The same state machine as
/// ``BufferDecoder``, but backed by a borrowed `RawSpan` + `Int` cursor instead
/// of an owned `ArraySlice<UInt8>`, so it never copies the source bytes.
///
/// It is `~Escapable`: its lifetime is tied to the `RawSpan` it borrows, so it
/// cannot outlive the memory it points at. Construct one inside the closure that
/// vends the bytes, e.g.:
///
/// ```swift
/// received.withUnsafeBytes { raw in
///     var decoder = SpanDecoder(RawSpan(_unsafeBytes: raw))
///     let message = try Message.decode(from: &decoder)
/// }
/// ```
@frozen public struct SpanDecoder: ~Escapable {
    @usableFromInline var span: RawSpan
    @usableFromInline var index: Int

    /// Creates a parsing view over the given `span`, with the cursor at the start.
    @_lifetime(copy span)
    @inlinable public init(_ span: RawSpan) {
        self.span = span
        self.index = 0
    }
}
extension SpanDecoder {
    /// The number of bytes remaining to be consumed. A safe upper bound on the
    /// element count a (possibly hostile) length header can require — every
    /// encoded element is at least one byte — so it should clamp speculative
    /// `reserveCapacity` calls, exactly as ``BufferDecoder/remaining`` does.
    @inlinable public var remaining: Int {
        self.span.byteCount - self.index
    }
}
extension SpanDecoder {
    /// Consumes and returns a single byte.
    @inlinable mutating func parse() throws(BufferDecodingError) -> UInt8 {
        guard self.index < self.span.byteCount else {
            throw self.expected(.bytes(1))
        }
        let byte: UInt8 = self.span.unsafeLoadUnaligned(
            fromByteOffset: self.index,
            as: UInt8.self
        )
        self.index += 1
        return byte
    }

    /// Consumes `size` bytes and yields a borrowed `RawSpan` view over exactly
    /// that region — no copy. The yielded span borrows the same underlying
    /// memory; the closure must not let it escape.
    @inlinable public mutating func parse<T>(
        size: Int,
        with yield: (RawSpan) -> T
    ) throws(BufferDecodingError) -> T {
        let start: Int = self.index
        guard size >= 0, start &+ size <= self.span.byteCount else {
            throw self.expected(.bytes(size))
        }
        self.index = start &+ size
        return yield(self.span.extracting(start ..< start &+ size))
    }

    /// Advances until encountering `byte`, leaving the cursor just past it, and
    /// yields a borrowed `RawSpan` over the bytes skipped (excluding the match).
    /// Scans the raw memory directly to avoid per-byte bounds checks.
    @discardableResult
    @inlinable public mutating func parse<T>(
        through byte: UInt8,
        with yield: (RawSpan) -> T
    ) throws(BufferDecodingError) -> T {
        let start: Int = self.index
        let count: Int = self.span.byteCount
        // `firstIndex(of:)` on the raw buffer lowers to a vectorized memchr and
        // returns an absolute offset (slices of `UnsafeRawBufferPointer` keep the
        // base index space), so no rebasing is needed.
        let match: Int? = self.span.withUnsafeBytes {
            (buffer: UnsafeRawBufferPointer) -> Int? in
            buffer[start ..< count].firstIndex(of: byte)
        }
        guard let match: Int else {
            self.index = count
            throw .expected(.byte(byte), encountered: 0)
        }
        self.index = match &+ 1
        return yield(self.span.extracting(start ..< match))
    }

    /// Asserts all available bytes have been consumed.
    @inlinable public func finish() throws(BufferDecodingError) {
        guard self.index == self.span.byteCount else {
            throw self.expected(.end)
        }
    }

    @inlinable func expected(
        _ expectation: BufferDecodingError.Expectation
    ) -> BufferDecodingError {
        .expected(expectation, encountered: self.span.byteCount - self.index)
    }
}
