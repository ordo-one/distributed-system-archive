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
