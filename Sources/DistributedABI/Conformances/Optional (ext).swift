extension Optional: Transferable where Wrapped: Transferable {
    /// An optional travels as one discriminant byte, 0 for nil and 1 for a value, then the
    /// value’s bytes.
    @inlinable public var transferSize: Int { 1 + (self?.transferSize ?? 0) }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        if  let self: Wrapped {
            output.append(1)
            self.transfer(into: &output)
        } else {
            output.append(0)
        }
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        switch try input.take(UInt8.self) {
        case 0: self = nil
        case 1: self = try Wrapped.init(transferring: &input)
        case let code: throw .init(.discriminant(.init(code)))
        }
    }
}
