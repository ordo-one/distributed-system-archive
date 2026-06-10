//  ZERO-COPY encode entry point (the ENCODE-side mirror of `SpanDecoder`).
//
//  `BufferEncoder` stores a `[UInt8]`, so producing wire bytes for a SwiftNIO
//  `ByteBuffer`, an LMDB `MDB_RESERVE` page, or any caller-provided
//  `UnsafeMutableRawBufferPointer` first encodes into that owned `Array` and
//  then COPIES the finished bytes into the destination. `SpanEncoder` is the
//  same serialization logic over a borrowed `OutputRawSpan`, so it writes the
//  bytes DIRECTLY into foreign memory with no `[UInt8]` staging buffer and no
//  send-side copy.
//
//  It emits the SAME wire format as `BufferEncoder` (little-endian fixed-width
//  integers, a format byte + null-terminated compact strings or 40-bit
//  length-prefixed long strings, a discriminant byte for optionals, and a
//  `CollectionHeader` for collections), so bytes written through `SpanEncoder`
//  decode byte-for-byte identically via `BufferDecoder` / `SpanDecoder`.
//
//  Because the destination is a fixed reserved region, the caller must know the
//  exact byte count up front. `SpanEncoder` does NOT grow: writes past
//  `freeCapacity` trap (an `OutputRawSpan` precondition). A producer therefore
//  runs a cheap size pass first (see the benchmark's `Message.encodedSize`) and
//  reserves exactly that many bytes. This matches the `MDB_RESERVE` /
//  `ByteBuffer.writeWithOutputRawSpan(minimumWritableBytes:)` contract.
//
//  Requires `-enable-experimental-feature Lifetimes` on THIS target only
//  (the `OutputRawSpan` field is `~Escapable` and the wrapper carries
//  `@_lifetime` annotations); clients linking the resilient
//  `OrdoDistributedABI` dylib do NOT need the flag, exactly like `SpanDecoder`.
//  Verified to build with `-enable-library-evolution`.
//
//  `SpanEncoder` is purely additive: it does not touch `BufferEncoder` and
//  reuses the existing wire-format vocabulary (`CollectionHeader`,
//  `String.BinaryFormat`, `Optional.BinaryFormat`).

/// A zero-copy serialization view over caller-provided memory. The same wire
/// format as ``BufferEncoder``, but backed by a borrowed `OutputRawSpan`
/// instead of an owned `[UInt8]`, so it writes the encoded bytes straight into
/// a reserved destination region with no staging buffer and no copy.
///
/// It is `~Escapable` (it borrows the `OutputRawSpan`'s memory) and `~Copyable`
/// (the cursor is single-owner), so it cannot outlive the buffer it writes
/// into. Construct one inside the scope that vends the writable region, e.g.
/// the closure of `ByteBuffer.writeWithOutputRawSpan` or over an LMDB reserved
/// page:
///
/// ```swift
/// reserved.withMemoryRebound(to: UInt8.self) { _ in }
/// var raw = OutputRawSpan(buffer: reserved, initializedCount: 0)
/// var encoder = SpanEncoder(raw)
/// message.encode(to: &encoder)
/// let written = encoder.finalize()        // byte count written
/// ```
@frozen public struct SpanEncoder: ~Copyable, ~Escapable {
    @usableFromInline var raw: OutputRawSpan

    /// Wraps an `OutputRawSpan` over the caller's reserved region. The encoder
    /// appends in place and never grows; the region must be at least
    /// ``Swift/OutputRawSpan/freeCapacity`` bytes, which the caller sizes via a
    /// preceding size pass.
    @_lifetime(copy raw)
    @inlinable public init(_ raw: consuming OutputRawSpan) {
        self.raw = raw
    }
}
extension SpanEncoder {
    /// The number of bytes written so far.
    @inlinable public var byteCount: Int {
        self.raw.byteCount
    }
    /// The number of bytes still available in the reserved region.
    @inlinable public var freeCapacity: Int {
        self.raw.freeCapacity
    }
}
extension SpanEncoder {
    /// Appends a single byte.
    @_lifetime(self: copy self)
    @inlinable public mutating func append(_ byte: UInt8) {
        self.raw.append(byte)
    }

    /// Appends a fixed-width integer in little-endian byte order, matching the
    /// wire format `BufferEncoder` produces via
    /// `withUnsafeBytes(of: self.littleEndian)`.
    @_lifetime(self: copy self)
    @inlinable public mutating func appendLittleEndian<T>(
        _ value: T
    ) where T: FixedWidthInteger & BitwiseCopyable {
        self.raw.append(value.littleEndian, as: T.self)
    }

    /// Appends a contiguous run of bytes (e.g. the UTF-8 code units of a
    /// string), copying them into the reserved region.
    @_lifetime(self: copy self)
    @inlinable public mutating func append(
        copying source: UnsafeRawBufferPointer
    ) {
        guard let base: UnsafeRawPointer = source.baseAddress, source.count > 0 else {
            return
        }
        // There is no safe `OutputRawSpan` bulk-copy entry point (no
        // `append(contentsOf: RawSpan)`), so the bulk copy goes through the
        // unsafe mutable-bytes escape, kept contained in-library exactly as the
        // task requires. `withUnsafeMutableBytes` hands us the FULL capacity
        // buffer plus an `inout initializedCount` cursor; we copy at the cursor
        // and bump it.
        let n: Int = source.count
        self.raw.withUnsafeMutableBytes {
            (dest: UnsafeMutableRawBufferPointer, initializedCount: inout Int) in
            //  Trap BEFORE the memcpy if the reserved region is too small: an
            //  under-sized reserve (a bug in the caller's size pass) must fail
            //  loudly rather than write past the region and only trip the
            //  OutputRawSpan capacity check after the bytes are already copied.
            precondition(
                initializedCount + n <= dest.count,
                "SpanEncoder: append(copying:) would overflow the reserved region"
            )
            dest.baseAddress!.advanced(by: initializedCount)
                .copyMemory(from: base, byteCount: n)
            initializedCount += n
        }
    }
}
extension SpanEncoder {
    /// Finalizes the encoder and returns the number of bytes written into the
    /// reserved region. The bytes are already in the caller's memory; there is
    /// nothing to copy out. The caller commits the underlying `OutputRawSpan`
    /// (e.g. via `OutputRawSpan.finalize(for:)` or the NIO closure return) in
    /// the scope that owns the reserved region.
    @inlinable public consuming func finalize() -> Int {
        self.raw.byteCount
    }
}
