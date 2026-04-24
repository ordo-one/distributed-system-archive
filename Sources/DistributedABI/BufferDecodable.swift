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
