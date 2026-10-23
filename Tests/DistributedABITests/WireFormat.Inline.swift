import DistributedABI
import Testing

extension WireFormat {
    /// A value built of inline arrays, with the fixed size its type must state and the bytes
    /// it must take, both written out rather than derived from the library. An inline array is
    /// not `Equatable`, so the value read back must write the same bytes again.
    struct Inline: Sendable {
        let name: String
        let stated: Int?
        let expected: Int?
        let golden: [UInt8]
        let size: Int
        let write: @Sendable () -> [UInt8]
        let reread: @Sendable ([UInt8]) throws(TransferError) -> [UInt8]

        init<Value>(
            _ value: Value,
            fixed expected: Int?,
            _ golden: [UInt8]
        ) where Value: Transferable {
            self.name = "\(Value.self)"
            self.stated = Value.fixedTransferSize
            self.expected = expected
            self.golden = golden
            self.size = value.transferSize
            self.write = { [UInt8].init(transferring: value) }
            self.reread = { (bytes: [UInt8]) throws(TransferError) in
                [UInt8].init(transferring: try Value.decode(bytes))
            }
        }
    }
}
extension WireFormat.Inline: CustomTestStringConvertible {
    var testDescription: String { self.name }
}
