@frozen @usableFromInline struct SetCollisionError<Element>: Error {
    @usableFromInline let position: Int

    @inlinable init(position: Int) {
        self.position = position
    }
}
extension SetCollisionError: CustomStringConvertible {
    @usableFromInline var description: String {
        """
        element collision at position [\(self.position)] in set of element type \
        \(String.init(reflecting: Element.self))
        """
    }
}
