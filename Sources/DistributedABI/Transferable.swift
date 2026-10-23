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

    /// Whether a value of this type is stored in memory exactly as its transfer bytes, so that
    /// an array of them can travel as one copy of its elements’ storage.
    ///
    /// A type that states this has a ``fixedTransferSize`` that is the size and the stride of
    /// its memory, holds no reference, and reads back as the value whose stored bytes are any
    /// bytes of that size: every bit pattern is a valid value. An array, a contiguous array, a
    /// slice or an inline array of such elements then writes their storage after the count
    /// with one copy, and reads it back with one copy, with the bytes on the wire unchanged.
    /// The collection checks the size, the stride and the absence of references itself, and
    /// writes and reads each element through its own conformance when any of them fails.
    ///
    /// The fixed-width integers state it on a little-endian host, as do `Float` and `Double`,
    /// whose wire form is their bit pattern. A type that wraps one of them as its only stored
    /// property, and travels as it does, states it by forwarding the wrapped type’s answer:
    ///
    /// ```swift
    /// @inlinable public static var isBitwiseTransferable: Bool {
    ///     RawValue.isBitwiseTransferable
    /// }
    /// ```
    ///
    /// A type with an integer raw value does not state it by default: an enumeration is stored
    /// as its case index rather than its raw value, and not every byte is a case. Neither does
    /// `Bool`, which reads only 0 and 1. The default is false.
    static var isBitwiseTransferable: Bool { get }

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
    @inlinable public static var isBitwiseTransferable: Bool { false }
}
extension Transferable {
    /// The fixed size of a value of this type when an array of them can travel as one copy of
    /// its storage: the type states ``isBitwiseTransferable``, and its fixed size is the size
    /// and the stride of its memory, which holds no reference. Nil otherwise, and then each
    /// element travels through its own conformance. Specialized for a type, this folds to a
    /// constant; through the witness table, it asks the type once per collection.
    @inlinable static var bitwiseTransferStride: Int? {
        guard Self.isBitwiseTransferable,
        let size: Int = Self.fixedTransferSize,
            size == MemoryLayout<Self>.size,
            size == MemoryLayout<Self>.stride,
        _isPOD(Self.self) else {
            return nil
        }
        return size
    }
}
extension Transferable
    where Self: FixedWidthInteger & BitwiseCopyable & ConvertibleFromBytes & ConvertibleToBytes {
    /// An integer travels as its fixed-width little-endian bytes.
    @inlinable public static var fixedTransferSize: Int? { MemoryLayout<Self>.size }
    /// On a little-endian host, an integer is stored as the bytes it travels as. A type that
    /// gives itself another wire form than this states false.
    @inlinable public static var isBitwiseTransferable: Bool {
        #if _endian(little)
        true
        #else
        false
        #endif
    }
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
