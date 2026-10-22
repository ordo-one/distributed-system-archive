/// A value the transport can carry.
///
/// A conformer states the exact size of its wire form, writes exactly that many bytes into
/// memory the destination owns, and reads itself back from bytes it borrows. It never frames
/// itself: the container that holds it (the transport for an argument, a collection for an
/// element, a composite for a field) records the length wherever the length is not fixed.
///
/// A value whose memory already is its wire form should conform to ``ContiguousTransferable``
/// instead, which supplies all three requirements from the bytes it lends.
public protocol Transferable: Sendable {
    /// The size of every value of this type, when it is the same for all of them, or nil.
    ///
    /// A collection of such elements packs them behind its count with no per-element length,
    /// and a type that states a fixed size must read exactly that many bytes in
    /// ``init(transferring:)``. The size is at least one byte.
    static var fixedTransferSize: Int? { get }

    /// The exact number of bytes ``transfer(into:)`` writes.
    var transferSize: Int { get }

    /// Writes exactly ``transferSize`` bytes into `output`, which has room for them.
    func transfer(into output: inout OutputRawSpan)

    /// Reads one value from `input`.
    ///
    /// A value of variable size that its container framed finds exactly its own bytes in
    /// `input`; a value of fixed size, or a composite, reads its parts in order. The bytes are
    /// borrowed from the transport’s buffer, and a value that keeps them copies them.
    init(transferring input: inout TransferReader) throws(TransferError)
}
extension Transferable {
    @inlinable public static var fixedTransferSize: Int? { nil }
}
extension Transferable {
    /// The size of this value as the part of a container: its bytes, preceded by a ULEB128
    /// length unless its type has a fixed size. This is what ``OutputRawSpan/append(framed:)``
    /// writes.
    @inlinable public var framedTransferSize: Int {
        let size: Int = self.transferSize
        if  case nil = Self.fixedTransferSize {
            return ULEB128.size(UInt.init(size)) + size
        } else {
            return size
        }
    }
}
extension Transferable
    where Self: FixedWidthInteger & BitwiseCopyable & ConvertibleFromBytes & ConvertibleToBytes {
    /// An integer travels as its fixed-width little-endian bytes.
    @inlinable public static var fixedTransferSize: Int? { MemoryLayout<Self>.size }
    @inlinable public var transferSize: Int { MemoryLayout<Self>.size }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        output.append(littleEndian: self)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self = try input.take(Self.self)
    }
}
extension Transferable where Self: RawRepresentable, RawValue: Transferable & FixedWidthInteger {
    /// A value with an integer raw value travels as its raw value; a raw value with no case is
    /// a ``TransferError/Kind/discriminant(_:)`` error.
    @inlinable public static var fixedTransferSize: Int? { RawValue.fixedTransferSize }
    @inlinable public var transferSize: Int { self.rawValue.transferSize }

    @inlinable public func transfer(into output: inout OutputRawSpan) {
        self.rawValue.transfer(into: &output)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        let rawValue: RawValue = try .init(transferring: &input)
        guard
        let value: Self = .init(rawValue: rawValue) else {
            // the raw value’s bits as they were on the wire, so a negative `Int8` reads as
            // the byte it was sent as
            let bits: UInt64 = .init(truncatingIfNeeded: rawValue)
            let mask: UInt64 = RawValue.bitWidth < 64 ? (1 << RawValue.bitWidth) - 1 : .max
            throw .init(.discriminant(bits & mask))
        }
        self = value
    }
}
