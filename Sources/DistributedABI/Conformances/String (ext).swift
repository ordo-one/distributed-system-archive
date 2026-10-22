extension String: Transferable {
    /// A string travels as its UTF-8 bytes as they are, with no terminator: its container
    /// frames the length. The bytes are lent with no allocation.
    @inlinable public var transferSize: Int { self.utf8.count }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        output.append(bytes: self.utf8Span.span.bytes)
    }
    /// Reads every remaining byte; bytes that are not valid UTF-8 are refused with the
    /// standard library’s validation error as the payload.
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        let utf8: UTF8Span
        do {
            utf8 = try .init(validating: .init(viewing: input.takeRemaining()))
        } catch {
            throw .payload(error)
        }
        self.init(copying: utf8)
    }
}
