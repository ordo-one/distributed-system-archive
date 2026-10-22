extension String: Transferable {
    /// A string travels as its UTF-8 bytes as they are, with no terminator: its container
    /// frames the length. The bytes of a native string are copied from its storage with no
    /// allocation; a string bridged from an `NSString` whose storage is not UTF-8 is
    /// transcoded first, which may allocate.
    @inlinable public var transferSize: Int { self.utf8.count }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        // `utf8Span` and `UTF8Span.span` are getters a client cannot inline, so the native
        // storage comes through `withContiguousStorageIfAvailable`, which inlines; its
        // pointer is viewed as a span at once, and only for the copy
        let copied: Void? = self.utf8.withContiguousStorageIfAvailable {
            output.append(bytes: unsafe $0.span.bytes)
        }
        if  case nil = copied {
            self.transfer(transcoding: &output)
        }
    }

    // a bridged string, out of line and away from every caller
    @usableFromInline @_alwaysEmitIntoClient @inline(never) func transfer(
        transcoding output: inout OutputRawSpan
    ) {
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
