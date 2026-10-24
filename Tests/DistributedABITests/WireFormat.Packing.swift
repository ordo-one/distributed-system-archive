import DistributedABI
import Testing

extension WireFormat {
    /// An array of values of one type, with the fixed size the type must state and the bytes
    /// the array must take, both written out rather than derived from the library.
    struct Packing: Sendable {
        let name: String
        let stated: Int?
        let expected: Int?
        let golden: [UInt8]
        let write: @Sendable () -> [UInt8]
        let read: @Sendable ([UInt8]) throws(TransferError) -> Bool

        init<Value>(
            _ values: [Value],
            fixed expected: Int?,
            _ golden: [UInt8]
        ) where Value: Transferable & Equatable {
            self.name = "\(Value.self)"
            self.stated = Value.transferLayout?.size
            self.expected = expected
            self.golden = golden
            self.write = { [UInt8].init(transferring: values) }
            self.read = { (bytes: [UInt8]) throws(TransferError) in
                try [Value].decode(bytes) == values
            }
        }
    }
}
extension WireFormat.Packing: CustomTestStringConvertible {
    var testDescription: String { self.name }
}
