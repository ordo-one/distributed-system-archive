extension Float: Transferable {
    /// A `Float` travels as its bit pattern, little-endian, so every NaN payload survives.
    @inlinable public static var fixedTransferSize: Int? { 4 }
    @inlinable public var transferSize: Int { 4 }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        output.append(littleEndian: self.bitPattern)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(bitPattern: try input.take(UInt32.self))
    }
}
