/// A type that can be decoded from the wire format, directly out of a borrowed
/// `RawSpan` with no copy. A single conformance serves both the zero-copy path
/// (a span over a received `ByteBuffer` / mmap) and the owned path (a span
/// borrowed from a `[UInt8]`); see ``decode(_:)-(ArraySlice<UInt8>)``.
///
/// The witness reads from `input` starting at `index` and advances `index` past
/// the bytes it consumed.
public protocol BufferDecodable {
    static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self
}
extension BufferDecodable where Self: FixedWidthInteger & BitwiseCopyable {
    /// Parses a little-endian integer.
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        try input.parseLittleEndian(Self.self, at: &index)
    }
}
extension BufferDecodable where Self: RawRepresentable, RawValue: BufferDecodable & Sendable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        let value: RawValue = try .decode(from: input, at: &index)
        guard
        let value: Self = .init(rawValue: value) else {
            throw .arbitrary(BufferDiscriminationError<RawValue, Self>.init(code: value))
        }
        return value
    }
}
extension BufferDecodable where Self: RangeReplaceableCollection, Element: BufferDecodable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        let header: CollectionHeader = try .decode(from: input, at: &index)
        var values: Self = .init()
        //  Clamp the speculative reservation to the bytes actually available: a
        //  hostile header can claim a huge count, but it cannot supply more
        //  elements than there are remaining bytes (each element is at least one
        //  byte). This prevents a 9-byte header from forcing a multi-gigabyte
        //  allocation before any element has been read.
        values.reserveCapacity(Swift.min(header.count, input.remaining(from: index)))
        for _: Int in 0 ..< header.count {
            let before: Int = index
            values.append(try Element.decode(from: input, at: &index))
            //  Guarantee forward progress: every element must consume at least one
            //  byte, otherwise a hostile 9-byte header could spin a client-supplied
            //  zero-byte element conformance up to `Int.max` iterations.
            guard index > before else {
                throw input.expected(.bytes(1), at: index)
            }
        }
        return values
    }
}
