import DistributedABI

/// A keyed collection of one’s own, which keeps its entries in order and may repeat a key,
/// conformed in the wire form of a dictionary through the library’s public helpers alone.
///
/// It reads and writes each key and each value on its own: the wire form interleaves them, and
/// it keeps them in two arrays, so no run of its storage is the bytes of its entries, and the
/// helpers that copy a collection’s storage at once, `TransferWriter.append(elements:)` and
/// `TransferReader.readElements(count:into:)`, do not apply.
struct Ledger<Key, Value> {
    let keys: [Key]
    let values: [Value]

    init(keys: [Key], values: [Value]) {
        precondition(keys.count == values.count)
        self.keys = keys
        self.values = values
    }
}
extension Ledger: Equatable where Key: Equatable, Value: Equatable {
}
extension Ledger: Sendable where Key: Sendable, Value: Sendable {
}
extension Ledger: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral entries: (Key, Value)...) {
        self.init(keys: entries.map(\.0), values: entries.map(\.1))
    }
}
extension Ledger: Transferable where Key: Transferable, Value: Transferable {
    var transferSize: Int {
        zip(self.keys, self.values).reduce(ULEB128.size(self.keys.count)) {
            $0 + $1.0.transferSize + $1.1.transferSize
        }
    }

    func transfer(into output: inout TransferWriter) {
        output.append(uleb128: self.keys.count)
        for (key, value): (Key, Value) in zip(self.keys, self.values) {
            output.append(element: key)
            output.append(element: value)
        }
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        let count: Int = try input.readCount(keys: Key.self, values: Value.self)
        var keys: [Key] = []
        var values: [Value] = []
        keys.reserveCapacity(count)
        values.reserveCapacity(count)
        for _: Int in 0 ..< count {
            keys.append(try input.read(Key.self))
            values.append(try input.read(Value.self))
        }
        self.init(keys: keys, values: values)
    }
}
