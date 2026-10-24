extension Dictionary: Transferable where Key: Transferable, Value: Transferable {
    /// A dictionary travels as a ULEB128 count, then each key followed by its value, in
    /// iteration order, each of which delimits itself. A key that repeats an earlier one is a
    /// ``TransferError/Kind/duplicate(at:)`` error.
    ///
    /// Keys or values of a fixed size are sized from the count alone, and the others are
    /// visited through ``Swift/Dictionary/keys`` or ``Swift/Dictionary/values``, never as
    /// key-value pairs: a pair is a tuple whose type metadata an unspecialized loop looks up
    /// for every entry.
    @inlinable public var transferSize: Int {
        var size: Int = ULEB128.size(self.count)
        if  let keySize: Int = Key.transferLayout?.size {
            size += self.count * keySize
        } else {
            for key: Key in self.keys {
                size += key.transferSize
            }
        }
        if  let valueSize: Int = Value.transferLayout?.size {
            size += self.count * valueSize
        } else {
            for value: Value in self.values {
                size += value.transferSize
            }
        }
        return size
    }

    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(uleb128: self.count)
        for (key, value): (Key, Value) in self {
            output.append(element: key)
            output.append(element: value)
        }
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        let count: Int = try input.readCount(keys: Key.self, values: Value.self)
        self.init(minimumCapacity: count)
        for i: Int in 0 ..< count {
            let key: Key = try input.read(Key.self)
            let value: Value = try input.read(Value.self)
            guard case nil = self.updateValue(value, forKey: key) else {
                throw .init(.duplicate(at: i))
            }
        }
    }
}
