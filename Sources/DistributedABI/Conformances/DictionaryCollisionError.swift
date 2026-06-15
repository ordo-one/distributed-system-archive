@frozen @usableFromInline struct DictionaryCollisionError<Key, Value>: Error {
    @usableFromInline let position: Int

    @inlinable init(position: Int) {
        self.position = position
    }
}
extension DictionaryCollisionError: CustomStringConvertible {
    @usableFromInline var description: String {
        """
        key collision at position [\(self.position)] in dictionary of type \
        [\(String.init(reflecting: Key.self)): \(String.init(reflecting: Value.self))]
        """
    }
}
