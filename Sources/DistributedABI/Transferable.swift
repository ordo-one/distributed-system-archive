/// A value the transport can carry.
///
/// A conformer states the exact size of its wire form, writes exactly that many bytes into
/// memory the destination owns, and reads itself back from bytes it borrows. Every value
/// delimits itself on the wire: a leaf of variable size (a string, a serialized message)
/// writes its ULEB128 length before its bytes, a collection its count (an inline array, whose
/// count is its type’s, writes none), an optional its discriminant, so a container or a
/// composite writes its parts one after another and reads them back in the same order, with
/// no length of its own around any of them.
///
/// A value whose memory already is its wire form should conform to ``ContiguousTransferable``
/// instead, which supplies all three requirements from the bytes it lends.
public protocol Transferable: Sendable {
    /// The size of every value of this type, when it is the same for all of them, or nil.
    ///
    /// A collection of such elements sizes itself from its count alone, and checks that each
    /// element read exactly that many bytes, so a type that states a fixed size must read
    /// exactly that many in ``init(transferring:)``. The size is at least one byte.
    static var fixedTransferSize: Int? { get }

    /// The exact number of bytes ``transfer(into:)`` writes, at least one.
    ///
    /// A collection refuses a count of elements that the bytes remaining could not hold at one
    /// byte each, before it reserves anything, so a value of no bytes would not read back from
    /// inside one. A composite with no fields writes a byte of its own, such as a version or a
    /// zero, and reads it back.
    var transferSize: Int { get }

    /// Writes exactly ``transferSize`` bytes into `output`, which has room for them.
    func transfer(into output: inout TransferWriter)

    /// Reads one value from `input`, consuming exactly the bytes ``transfer(into:)`` wrote for
    /// it and no more: the parts that follow it in `input` belong to the values after it. The
    /// bytes are borrowed from the transport’s buffer, and a value that keeps them copies them.
    init(transferring input: inout TransferReader) throws(TransferError)
}
extension Transferable {
    @inlinable public static var fixedTransferSize: Int? { nil }
}
extension Transferable
    where Self: FixedWidthInteger & BitwiseCopyable & ConvertibleFromBytes & ConvertibleToBytes {
    /// An integer travels as its fixed-width little-endian bytes.
    @inlinable public static var fixedTransferSize: Int? { MemoryLayout<Self>.size }
    @inlinable public var transferSize: Int { MemoryLayout<Self>.size }

    @inlinable public func transfer(into output: inout TransferWriter) {
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

    @inlinable public func transfer(into output: inout TransferWriter) {
        self.rawValue.transfer(into: &output)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        let rawValue: RawValue = try .init(transferring: &input)
        guard
        let value: Self = .init(rawValue: rawValue) else {
            // the raw value’s bits as they were on the wire, so a negative `Int8` reads as
            // the byte it was sent as
            let bits: UInt128 = .init(truncatingIfNeeded: rawValue)
            let mask: UInt128 = RawValue.bitWidth < 128 ? (1 << RawValue.bitWidth) - 1 : .max
            throw .init(.discriminant(bits & mask))
        }
        self = value
    }
}
