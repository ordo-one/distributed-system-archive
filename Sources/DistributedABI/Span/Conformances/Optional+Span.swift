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
