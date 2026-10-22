extension Substring: Transferable {
    /// A substring travels exactly as a ``Swift/String`` with the same contents.
    @inlinable public var transferSize: Int { self.utf8.count }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        // the native storage through an inlinable call, as `String.transfer(into:)` takes
        // it; unlike the string’s, the substring’s method is not marked safe
        let copied: Void? = unsafe self.utf8.withContiguousStorageIfAvailable {
            output.append(bytes: unsafe $0.span.bytes)
        }
        if  case nil = copied {
            self.transfer(transcoding: &output)
        }
    }

    // a substring of a bridged string, out of line and away from every caller
    @usableFromInline @_alwaysEmitIntoClient @inline(never) func transfer(
        transcoding output: inout OutputRawSpan
    ) {
        output.append(bytes: self.utf8Span.span.bytes)
    }

    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(try String.init(transferring: &input))
    }
}
