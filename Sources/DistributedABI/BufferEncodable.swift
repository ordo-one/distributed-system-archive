/// A type that can be encoded to the wire format, written directly into a
/// borrowed `OutputRawSpan` with no staging buffer. A single conformance serves
/// both the zero-copy path (writing into a reserved NIO/LMDB region) and the
/// owned path (``encoded()``).
///
/// ``encodedSize`` is an UPPER BOUND on the number of bytes ``encode(into:)``
/// will write — exact for fixed-width and aggregate-of-fixed-width types, and a
/// small over-estimate for variable-length payloads (a string reserves as if it
/// used the `long` framing, avoiding a second compact/long scan in the size
/// pass). Callers reserve `encodedSize` bytes; the encoder writes the exact
/// bytes and reports the true count.
public protocol BufferEncodable {
    func encode(into output: inout OutputRawSpan)
    var encodedSize: Int { get }
}
extension BufferEncodable where Self: FixedWidthInteger & BitwiseCopyable {
    /// Serializes a fixed-width integer in little-endian byte order.
    @inlinable public func encode(into output: inout OutputRawSpan) {
        output.append(self.littleEndian, as: Self.self)
    }
    @inlinable public var encodedSize: Int { MemoryLayout<Self>.size }
}
extension BufferEncodable where Self: RawRepresentable, RawValue: BufferEncodable {
    @inlinable public func encode(into output: inout OutputRawSpan) {
        self.rawValue.encode(into: &output)
    }
    @inlinable public var encodedSize: Int { self.rawValue.encodedSize }
}
extension BufferEncodable where Self: Collection, Element: BufferEncodable {
    @inlinable public func encode(into output: inout OutputRawSpan) {
        self.header.encode(into: &output)
        for element: Element in self {
            element.encode(into: &output)
        }
    }
    @inlinable public var encodedSize: Int {
        var size: Int = self.header.encodedSize
        for element: Element in self {
            size += element.encodedSize
        }
        return size
    }
}
