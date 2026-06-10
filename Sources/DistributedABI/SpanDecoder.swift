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

//  MARK: - CollectionHeader (zero-copy decode)

extension CollectionHeader {
    /// Decodes a collection header from a ``SpanDecoder``. This mirrors the
    /// `BufferDecoder` path in `CollectionHeader.swift` byte-for-byte (1 byte if
    /// the count is < 255, otherwise `0xFF` followed by a little-endian `Int`),
    /// including the DoS hardening that rejects a negative count up front. The
    /// `BufferDecoder` overload in `CollectionHeader.swift` is left untouched.
    @inlinable static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        let first: UInt8 = try .decode(from: &input)
        if  first == .max {
            let count: Int = try .decode(from: &input)
            //  A negative count is never valid and would trap the `0 ..< count`
            //  loops that consume collection elements; reject it up front.
            guard count >= 0 else {
                throw input.expected(.bytes(0))
            }
            return .init(count: count)
        } else {
            return .init(count: Int.init(first))
        }
    }
}

//  MARK: - Decoding protocol (mirrors `BufferDecodable`, but `inout SpanDecoder`)

/// Mirror of ``BufferDecodable`` over a zero-copy ``SpanDecoder``. A protocol
/// requirement with a `~Escapable` `inout` parameter is permitted under the
/// Lifetimes feature.
public protocol SpanDecodable {
    associatedtype DeserializationError: Error
    static func decode(from input: inout SpanDecoder) throws(DeserializationError) -> Self
}
extension SpanDecodable where Self: FixedWidthInteger & BitwiseCopyable {
    /// Parses a little-endian integer (same wire format as the `ArraySlice` path).
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        try input.parse(size: MemoryLayout<Self>.size) {
            (region: RawSpan) -> Self in
            .init(littleEndian: region.unsafeLoadUnaligned(fromByteOffset: 0, as: Self.self))
        }
    }
}
extension SpanDecodable where Self: RawRepresentable, RawValue: SpanDecodable & Sendable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        let value: RawValue

        do {
            value = try .decode(from: &input)
        } catch let error as BufferDecodingError {
            throw error
        } catch {
            throw .arbitrary(error)
        }

        guard
        let value: Self = .init(rawValue: value) else {
            throw .arbitrary(BufferDiscriminationError<RawValue, Self>.init(code: value))
        }
        return value
    }
}
extension SpanDecodable where Self: RangeReplaceableCollection, Element: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        let header: CollectionHeader = try .decode(from: &input)
        var values: Self = .init()
        //  Clamp the speculative reservation to the bytes actually available: a hostile
        //  header can claim a huge count, but it cannot supply more elements than there
        //  are remaining bytes (each element is at least one byte). This prevents a
        //  9-byte header from forcing a multi-gigabyte allocation before any element
        //  has been read. Capacity still grows organically if the count is genuine.
        values.reserveCapacity(Swift.min(header.count, input.remaining))
        for _: Int in 0 ..< header.count {
            do {
                values.append(try .decode(from: &input))
            } catch let error as BufferDecodingError {
                throw error
            } catch {
                throw .arbitrary(error)
            }
        }

        return values
    }
}

//  MARK: - Scalar conformances

extension Bool: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        switch try input.parse() {
        case 0:
            return false
        case 1:
            return true
        case let code:
            throw .arbitrary(BufferDiscriminationError<UInt8, Self>.init(code: code))
        }
    }
}

extension Int8: SpanDecodable {}
extension Int16: SpanDecodable {}
extension Int32: SpanDecodable {}
extension Int64: SpanDecodable {}
extension Int: SpanDecodable {}
extension UInt8: SpanDecodable {}
extension UInt16: SpanDecodable {}
extension UInt32: SpanDecodable {}
extension UInt64: SpanDecodable {}
extension UInt: SpanDecodable {}

extension Double: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        .init(bitPattern: try .decode(from: &input))
    }
}
extension Float: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        .init(bitPattern: try .decode(from: &input))
    }
}

//  MARK: - String / Substring

extension String: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        //  `String.BinaryFormat`: .compact = 0, .long = 1, .none = 2.
        let format: UInt8 = try input.parse()
        switch format {
        case 0:     // .compact — null-terminated UTF-8
            return try input.parse(through: 0x00) {
                (region: RawSpan) -> String in
                region.withUnsafeBytes { String(decoding: $0, as: Unicode.UTF8.self) }
            }
        case 1:     // .long — length-prefixed UTF-8
            let low: UInt32 = try .decode(from: &input)
            let high: UInt8 = try .decode(from: &input)
            // shift on `UInt64` so the `<< 32` is well-defined on 32-bit too
            let size: Int = .init(UInt64(high) << 32 | UInt64(low))
            return try input.parse(size: size) {
                (region: RawSpan) -> String in
                region.withUnsafeBytes { String(decoding: $0, as: Unicode.UTF8.self) }
            }
        case 2:     // .none — empty
            return ""
        case let code:
            //  Invalid `String.BinaryFormat` discriminant. The `ArraySlice` path
            //  surfaces this through the format enum's `RawRepresentable` decode as a
            //  `BufferDiscriminationError`; mirror that exactly.
            throw .arbitrary(
                BufferDiscriminationError<UInt8, String.BinaryFormat>.init(code: code)
            )
        }
    }
}

extension Substring: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        try String.decode(from: &input)[...]
    }
}

//  MARK: - Optional

extension Optional: SpanDecodable where Wrapped: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        //  `Optional.BinaryFormat`: .none = 0, .some = 1.
        let format: UInt8 = try input.parse()
        switch format {
        case 0:     // .none
            return nil
        case 1:     // .some
            do {
                return try Wrapped.decode(from: &input)
            } catch let error as BufferDecodingError {
                throw error
            } catch {
                throw .arbitrary(error)
            }
        case let code:
            throw .arbitrary(
                BufferDiscriminationError<UInt8, Optional<Wrapped>.BinaryFormat>.init(code: code)
            )
        }
    }
}

//  MARK: - Collections

extension Array: SpanDecodable where Element: SpanDecodable {}
extension ArraySlice: SpanDecodable where Element: SpanDecodable {}

extension Set: SpanDecodable where Element: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        let header: CollectionHeader = try .decode(from: &input)
        var values: Self = []
        //  Clamp the speculative reservation to the available bytes (see Array.decode).
        values.reserveCapacity(Swift.min(header.count, input.remaining))
        for i: Int in 0 ..< header.count {
            let value: Element
            do {
                value = try .decode(from: &input)
            } catch let error as BufferDecodingError {
                throw error
            } catch {
                throw .arbitrary(error)
            }

            guard case (inserted: true, _) = values.insert(value) else {
                throw .arbitrary(SetCollisionError<Element>.init(position: i))
            }
        }

        return values
    }
}

extension Dictionary: SpanDecodable where Key: SpanDecodable, Value: SpanDecodable {
    @inlinable public static func decode(
        from input: inout SpanDecoder
    ) throws(BufferDecodingError) -> Self {
        let header: CollectionHeader = try .decode(from: &input)
        //  Clamp the speculative reservation to the available bytes (see Array.decode).
        //  A key/value pair needs at least two bytes, so `remaining` is a safe bound.
        var fields: Self = .init(minimumCapacity: Swift.min(header.count, input.remaining))
        for i: Int in 0 ..< header.count {
            let field: Key
            let value: Value
            do {
                field = try .decode(from: &input)
                value = try .decode(from: &input)
            } catch let error as BufferDecodingError {
                throw error
            } catch {
                throw .arbitrary(error)
            }
            switch fields.updateValue(value, forKey: field) {
            case nil:
                continue
            case _?:
                throw .arbitrary(DictionaryCollisionError<Key, Value>.init(position: i))
            }
        }

        return fields
    }
}
