extension Result: Transferable where Success: Transferable, Failure: Transferable {
    /// A result travels as one discriminant byte, 0 for success and 1 for failure, then the
    /// payload’s bytes.
    @inlinable public var transferSize: Int {
        switch self {
        case .success(let self): 1 + self.transferSize
        case .failure(let self): 1 + self.transferSize
        }
    }

    @inlinable public func transfer(into output: inout TransferWriter) {
        switch self {
        case .success(let self):
            output.append(0)
            self.transfer(into: &output)
        case .failure(let self):
            output.append(1)
            self.transfer(into: &output)
        }
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        switch try input.readByte() {
        case 0: self = .success(try .init(transferring: &input))
        case 1: self = .failure(try .init(transferring: &input))
        case let code: throw .init(.invalidDiscriminant(.init(code)))
        }
    }
}
