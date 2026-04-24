public protocol BufferEncodable {
    associatedtype SerializationError: Error
    func encode(to output: inout BufferEncoder) throws(SerializationError)
}
extension BufferEncodable where Self: FixedWidthInteger & BitwiseCopyable {
    /// Serializes a fixed-width integer in little-endian byte order.
    @inlinable public func encode(to output: inout BufferEncoder) {
        // the old version of DistributedABI did not care about endianness, which was bad...
        withUnsafeBytes(of: self.littleEndian) { output.append($0) }
    }
}
extension BufferDecodable where Self: RawRepresentable, RawValue: BufferEncodable {
    @inlinable public func encode(
        to output: inout BufferEncoder
    ) throws(RawValue.SerializationError) {
        try self.rawValue.encode(to: &output)
    }
}
