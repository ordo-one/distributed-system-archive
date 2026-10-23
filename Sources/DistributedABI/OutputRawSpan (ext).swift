extension OutputRawSpan {
    /// Lends this span to `body` as a ``TransferWriter``, and takes it back with every byte
    /// `body` wrote: the one call a transport makes to write values into a frame.
    @inlinable @inline(always) public mutating func withTransferWriter<Result>(
        _ body: (inout TransferWriter) -> Result
    ) -> Result {
        var writer: TransferWriter = .init(consume self)
        let result: Result = body(&writer)
        self = writer.output
        return result
    }
}
