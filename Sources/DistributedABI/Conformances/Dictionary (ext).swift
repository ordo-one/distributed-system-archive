extension Dictionary: Transferable where Key: Transferable, Value: Transferable {
    /// A dictionary travels as a ULEB128 count, then each key followed by its value, in
    /// iteration order, each of which delimits itself. A key that repeats an earlier one is a
    /// ``TransferError/Kind/duplicate(_:)`` error.
    @inlinable public var transferSize: Int {
        self.reduce(ULEB128.size(UInt.init(self.count))) {
            $0 + $1.key.transferSize + $1.value.transferSize
        }
    }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        output.append(uleb128: UInt.init(self.count))
        for (key, value): (Key, Value) in self {
            key.transfer(into: &output)
            value.transfer(into: &output)
        }
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        let count: Int = try input.takeCount(keys: Key.self, values: Value.self)
        self.init(minimumCapacity: count)
        for i: Int in 0 ..< count {
            let key: Key = try input.takeElement(Key.self)
            let value: Value = try input.takeElement(Value.self)
            guard case nil = self.updateValue(value, forKey: key) else {
                throw .init(.duplicate(i))
            }
        }
    }
}
