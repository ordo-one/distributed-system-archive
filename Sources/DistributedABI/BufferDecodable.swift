public protocol BufferDecodable {
    associatedtype DeserializationError: Error
    static func decode(from input: inout BufferDecoder) throws(DeserializationError) -> Self
}
extension BufferDecodable where Self: FixedWidthInteger & BitwiseCopyable {
    /// Parses a little-endian integer.
    @inlinable public static func decode(
        from input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        try input.parse(size: MemoryLayout<Self>.size) {
            $0.withUnsafeBytes {
                .init(littleEndian: $0.loadUnaligned(as: Self.self))
            }
        }
    }
}
extension BufferDecodable where Self: RawRepresentable, RawValue: BufferDecodable & Sendable {
    @inlinable public static func decode(
        from input: inout BufferDecoder
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
extension BufferDecodable where Self: RangeReplaceableCollection, Element: BufferDecodable {
    @inlinable public static func decode(
        from input: inout BufferDecoder
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
