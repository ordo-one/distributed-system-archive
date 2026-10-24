import DistributedABI

extension Transferable {
    /// Reads one value from all of `bytes`, refusing any byte left over.
    @inlinable static func decode(_ bytes: [UInt8]) throws(TransferError) -> Self {
        var input: TransferReader = .init(bytes.span.bytes)
        let value: Self = try .init(transferring: &input)
        try input.readEnd()
        return value
    }
}
