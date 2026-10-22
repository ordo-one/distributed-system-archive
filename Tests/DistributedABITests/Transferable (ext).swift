import DistributedABI

extension Transferable {
    /// Reads one value from all of `bytes`, refusing any byte left over.
    static func decode(_ bytes: [UInt8]) throws(TransferError) -> Self {
        var input: TransferReader = .init(bytes.span.bytes)
        let value: Self = try .init(transferring: &input)
        try input.finish()
        return value
    }

    /// Reads one value as the part of a container from all of `bytes`.
    static func decode(framed bytes: [UInt8]) throws(TransferError) -> Self {
        var input: TransferReader = .init(bytes.span.bytes)
        let value: Self = try input.take(framed: Self.self)
        try input.finish()
        return value
    }
}
