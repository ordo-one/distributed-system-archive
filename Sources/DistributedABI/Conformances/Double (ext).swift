extension Double: Transferable {
    /// A `Double` travels as its bit pattern, little-endian, so every NaN payload survives.
    /// On a little-endian host, the value is stored as the bit pattern it travels as.
    @inlinable public static var transferLayout: TransferLayout? {
        #if _endian(little)
        .bitwise(size: 8)
        #else
        .fixed(size: 8)
        #endif
    }
    @inlinable public var transferSize: Int { 8 }

    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(littleEndian: self.bitPattern)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(bitPattern: try input.read(littleEndian: UInt64.self))
    }
}
