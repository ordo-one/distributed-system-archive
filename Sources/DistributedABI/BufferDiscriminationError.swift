@frozen @usableFromInline struct BufferDiscriminationError<Code, Case>: Error
    where Code: Sendable {
    @usableFromInline let code: Code

    @inlinable init(code: Code) {
        self.code = code
    }
}
extension BufferDiscriminationError: CustomStringConvertible {
    @usableFromInline var description: String {
        "invalid discriminant (\(self.code)) for type '\(String.init(reflecting: Case.self))'"
    }
}
