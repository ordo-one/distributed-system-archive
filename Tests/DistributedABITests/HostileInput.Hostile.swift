import DistributedABI
import Testing

extension HostileInput {
    struct Hostile: Sendable {
        let name: String
        let bytes: [UInt8]
        let decode: @Sendable ([UInt8]) throws(TransferError) -> Void
        let expected: Expectation

        init<Value>(
            _ name: String,
            _ bytes: [UInt8],
            as _: Value.Type,
            _ expected: Expectation
        ) where Value: Transferable {
            self.name = name
            self.bytes = bytes
            self.decode = { (bytes: [UInt8]) throws(TransferError) in
                _ = try Value.decode(bytes)
            }
            self.expected = expected
        }
    }
}
extension HostileInput.Hostile: CustomTestStringConvertible {
    var testDescription: String { self.name }
}
