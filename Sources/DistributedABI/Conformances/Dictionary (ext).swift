extension Dictionary: Transferable where Key: Transferable, Value: Transferable {
    /// A dictionary travels as a ULEB128 count, then each key followed by its value, in
    /// iteration order, each of which delimits itself. A key that repeats an earlier one is a
    /// ``TransferError/Kind/duplicate(at:)`` error.
    ///
    /// Keys or values of a fixed size are sized from the count alone. Specialized for keys and
    /// values that both vary in size, the table is visited once, as key-value pairs; otherwise
    /// the keys or values that vary are visited through ``Swift/Dictionary/keys`` or
    /// ``Swift/Dictionary/values``, never as pairs, since a pair is a tuple whose type metadata
    /// an unspecialized body looks up even when it does not visit them.
    @inlinable public var transferSize: Int {
        var size: Int = ULEB128.size(self.count)
        if  _isConcrete(Key.self), _isConcrete(Value.self),
            case nil = Key.transferLayout,
            case nil = Value.transferLayout {
            return size + self.entriesTransferSize
        }
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

    /// The sizes of every key and every value, visited as pairs in one pass over the table,
    /// which a specialized client takes in place of one pass over the keys and another over the
    /// values: 1.15 times fewer instructions for a `[String: String]`. Out of line, so that the
    /// tuple metadata of a pair stays out of the unspecialized ``transferSize``.
    @inlinable @inline(never) var entriesTransferSize: Int {
        var size: Int = 0
        for (key, value): (Key, Value) in self {
            size += key.transferSize + value.transferSize
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
