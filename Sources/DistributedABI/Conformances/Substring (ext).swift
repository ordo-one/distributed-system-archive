extension Substring: Transferable {
    /// A substring travels exactly as a ``Swift/String`` with the same contents.
    @inlinable public var transferSize: Int { self.utf8.count }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        output.append(bytes: self.utf8Span.span.bytes)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(try String.init(transferring: &input))
    }
}
