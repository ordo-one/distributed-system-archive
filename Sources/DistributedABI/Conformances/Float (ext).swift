extension Float: Transferable {
    /// A `Float` travels as its bit pattern, little-endian, so every NaN payload survives.
    /// On a little-endian host, the value is stored as the bit pattern it travels as.
    @inlinable public static var transferLayout: TransferLayout? {
        #if _endian(little)
        .bitwise(size: 4)
        #else
        .fixed(size: 4)
        #endif
    }
    @inlinable public var transferSize: Int { 4 }

    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(littleEndian: self.bitPattern)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(bitPattern: try input.read(littleEndian: UInt32.self))
    }
}
