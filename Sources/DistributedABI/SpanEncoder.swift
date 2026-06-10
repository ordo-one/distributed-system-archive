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
///
/// ## Composable generic encode
///
/// `SpanEncoder` deliberately exposes only CONCRETE, overloaded leaf write
/// methods (`append(_: Bool)`, `append(_: Double)`, `append(_: String)`,
/// `append(collectionHeader:)`, `appendLittleEndian`, …). There is NO
/// `SpanEncodable` protocol — that omission is intentional. Encoding a generic
/// aggregate such as `Array<T>` or `Dictionary<K, V>` therefore requires the
/// caller (or codegen) to write the `CollectionHeader` via
/// ``append(collectionHeader:)`` and then loop, calling the correct leaf method
/// per element; the library does not dispatch that generically. A composable
/// `encode(to:)`-style protocol would require introducing a `SpanEncodable`
/// witness, which is explicitly out of scope here.
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
    //  Concrete wire-format write methods — the encode-side mirror of the
    //  `BufferEncodable` conformances in `Conformances/`. Each writes the SAME
    //  bytes its `encode(to: inout BufferEncoder)` counterpart produces, so a
    //  message written through these decodes byte-for-byte identically through
    //  `BufferDecoder` / `SpanDecoder`. They are CONCRETE overloads, NOT a
    //  protocol (see the type doc comment): a generic `Array`/`Dictionary` still
    //  needs the caller to write a header via ``append(collectionHeader:)`` and
    //  loop over the right leaf method.

    /// Appends a `Bool` as a single byte (`1` for `true`, `0` for `false`),
    /// matching `Bool.encode(to: inout BufferEncoder)`.
    @_lifetime(self: copy self)
    @inlinable public mutating func append(_ value: Bool) {
        self.append(value ? UInt8(1) : UInt8(0))
    }

    /// Appends a `Double` as its IEEE-754 `bitPattern` (a `UInt64`) in
    /// little-endian byte order, matching `Double.encode(to: inout BufferEncoder)`
    /// which forwards to `self.bitPattern.encode(to:)`.
    @_lifetime(self: copy self)
    @inlinable public mutating func append(_ value: Double) {
        self.appendLittleEndian(value.bitPattern)
    }

    /// Appends a `Float` as its IEEE-754 `bitPattern` (a `UInt32`) in
    /// little-endian byte order, matching `Float.encode(to: inout BufferEncoder)`
    /// which forwards to `self.bitPattern.encode(to:)`.
    @_lifetime(self: copy self)
    @inlinable public mutating func append(_ value: Float) {
        self.appendLittleEndian(value.bitPattern)
    }

    /// Appends a `String` in the wire format `String`/`Substring` produce:
    /// a format byte then payload. Byte-identical to
    /// `Substring.encode(to: inout BufferEncoder)`:
    ///
    /// - empty -> format `2` (`.none`), no payload;
    /// - compact (format `0`) iff the UTF-8 is `<= 256` code units AND contains
    ///   no `0x00` byte -> the UTF-8 bytes followed by a trailing `0x00`;
    /// - long (format `1`) otherwise -> a 40-bit length as `UInt32` low +
    ///   `UInt8` high (computed through `UInt64`, so the `>> 32` is well-defined
    ///   on 32-bit platforms) followed by the raw UTF-8 bytes.
    @_lifetime(self: copy self)
    @inlinable public mutating func append(_ string: String) {
        //  `withUTF8` makes the string's UTF-8 contiguous (a no-op for the native
        //  strings that dominate in practice) and yields a borrowed buffer; the
        //  whole encode happens inside, in one bounds-check-free scan + one bulk
        //  copy, allocation-free. The `count <= 256 && !contains(0)` rule is the
        //  format choice from `Substring.encode(to:)`; over a contiguous buffer it
        //  is identical to that path's `withContiguousStorageIfAvailable` fast path
        //  AND to its generic `i < 256` fallback scan (both pick compact for the
        //  same strings), so the bytes are identical. A `~Copyable` / `~Escapable`
        //  encoder CAN be mutated through this non-escaping closure.
        var local: String = string
        local.withUTF8 { (utf8: UnsafeBufferPointer<UInt8>) in
            if  utf8.isEmpty {
                self.append(UInt8(2))  // String.BinaryFormat.none
                return
            }
            let compact: Bool = utf8.count <= 256 && !utf8.contains(0)
            self.appendStringPayload(UnsafeRawBufferPointer(utf8), compact: compact)
        }
    }

    /// Appends a `Substring` in the wire format `Substring` produces; see
    /// ``append(_:)-(String)``. Byte-identical to
    /// `Substring.encode(to: inout BufferEncoder)`.
    @_lifetime(self: copy self)
    @inlinable public mutating func append(_ substring: Substring) {
        self.append(String(substring))
    }

    /// Shared tail for ``append(_:)-(Substring)``: writes the format byte and the
    /// UTF-8 payload. `utf8` must be non-empty. `compact` selects format `0`
    /// (UTF-8 + trailing `0x00`) vs format `1` (40-bit length prefix + UTF-8).
    @_lifetime(self: copy self)
    @inlinable mutating func appendStringPayload(
        _ utf8: UnsafeRawBufferPointer,
        compact: Bool
    ) {
        if  compact {
            self.append(UInt8(0))      // String.BinaryFormat.compact
            self.append(copying: utf8)
            self.append(UInt8(0x00))
        } else {
            //  1 TB ought to be enough for anyone. Compute the 40-bit length
            //  through `UInt64` so the `>> 32` is well-defined on 32-bit
            //  platforms too (the bytes emitted are identical on 64-bit).
            let size: UInt64 = .init(utf8.count)
            let high: UInt8 = .init(size >> 32)
            let low: UInt32 = .init(truncatingIfNeeded: size)

            self.append(UInt8(1))      // String.BinaryFormat.long
            self.appendLittleEndian(low)
            self.append(high)
            self.append(copying: utf8)
        }
    }

    /// Appends a `CollectionHeader` for a collection of `count` elements,
    /// byte-identical to `CollectionHeader.encode(to: inout BufferEncoder)`:
    /// a single byte equal to `count` when `count < 255`, otherwise `0xFF`
    /// followed by `count` as a little-endian `Int`. The caller writes this
    /// header, then loops over the elements calling the matching leaf method
    /// (there is no generic dispatch — see the type doc comment).
    @_lifetime(self: copy self)
    @inlinable public mutating func append(collectionHeader count: Int) {
        if  count < 255 {
            self.append(UInt8(count))
        } else {
            self.append(UInt8.max)     // 0xFF sentinel
            self.appendLittleEndian(count)
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
