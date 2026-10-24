extension Substring: Transferable {
    /// A substring travels exactly as a ``Swift/String`` with the same contents.
    @inlinable public var transferSize: Int {
        let count: Int = self.utf8.count
        return ULEB128.size(count) + count
    }

    @inlinable public func transfer(into output: inout TransferWriter) {
        // the native storage through an inlinable call, as `String.transfer(into:)` takes
        // it; unlike the string’s, the substring’s method is not marked safe
        let copied: Void? = unsafe self.utf8.withContiguousStorageIfAvailable {
            output.append(prefixed: unsafe $0.span.bytes)
        }
        if  case nil = copied {
            self.transfer(transcoding: &output)
        }
    }

    // a substring of a bridged string, out of line and away from every caller, one byte at
    // a time: `utf8Span` would measure all the text before the substring on every write
    @usableFromInline @_alwaysEmitIntoClient @inline(never) func transfer(
        transcoding output: inout TransferWriter
    ) {
        output.append(uleb128: self.utf8.count)
        for byte: UInt8 in self.utf8 {
            output.append(byte)
        }
    }

    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(try String.init(transferring: &input))
    }
}
