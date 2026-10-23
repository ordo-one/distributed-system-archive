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
    /// its memory, holds no reference or pointer of any kind, and reads back as the value whose
    /// stored bytes are any bytes of that size: every bit pattern is a valid value. An array, a
    /// contiguous array, a slice or an inline array of such elements then writes their storage
    /// after the count with one copy, and reads it back with one copy, with the bytes on the
    /// wire unchanged. The collection checks the size and the stride itself, and that the type
    /// holds no strong, weak or unowned reference, and writes and reads each element through
    /// its own conformance when any of them fails. It cannot see an `unowned(unsafe)`
    /// reference, an `Unmanaged` one or a raw pointer, which its memory holds as plain bits:
    /// a type that states this must hold none of them, which is the conformer’s guarantee.
    ///
    /// This is a requirement rather than a marker protocol because the generic conformances of
    /// the collections make the choice: through the witness table, a requirement is one call
    /// and folds away when specialized, where asking for a protocol is a dynamic cast per
    /// collection; and a derive macro states it by computing it from its fields’ own statements
    /// and their `MemoryLayout`, which a conformance to a protocol cannot depend on.
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

    /// The number of discriminants of a type stored as one byte that is its transfer byte, the
    /// bytes from zero up to that number, so that an array of them can travel as one copy of
    /// its storage, each byte checked against that number before it is copied. Nil for any
    /// other type, and by default.
    ///
    /// `Bool` states 2: it is stored as the byte 0 or 1 it travels as. An enumeration with no
    /// payload is stored as its case index, which Swift’s type layout makes the cases’
    /// declaration order, in one byte for two to 256 cases; when its raw values are `UInt8`
    /// and are exactly those indices, its stored byte is its transfer byte, and it can state
    /// its case count.
    ///
    /// The statement is not meant to be written by hand. The SDK’s generator emits it for the
    /// enumerations it generates, and ordo-sdk’s derive macro for a plugin’s own, each after
    /// checking from the declaration that the enumeration has no payload and that its raw
    /// values are implicit or exactly its case indices, and counting the cases: for five such
    /// cases, the conformance they generate carries `bitwiseDiscriminantCount` returning 5.
    ///
    /// A statement written by hand must guarantee the same: a type stored in one byte, each
    /// value stored as the byte it travels as, and every byte below the count a value. The
    /// collection checks the size, the stride and the fixed size of one byte itself, and
    /// reads each element through its own conformance when any of them fails; it refuses the
    /// first byte at or above the count with the ``TransferError/Kind/discriminant(_:)`` error
    /// a read of one value at a time reports, and leaves the reader just past it, where that
    /// read leaves it. It cannot check the rest, and nothing reports a wrong statement: a byte
    /// out of range is refused only from the stated count up, so a count above the number of
    /// cases accepts a byte of no case as a value of the type, and a count or raw values that
    /// do not match the cases read a byte as the wrong case, silently.
    static var bitwiseDiscriminantCount: Int? { get }

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
    @inlinable public static var bitwiseDiscriminantCount: Int? { nil }
}
extension Transferable {
    /// The fixed size of a value of this type when an array of them can travel as one copy of
    /// its storage: the type states ``isBitwiseTransferable``, its fixed size is the size and
    /// the stride of its memory, and that memory is trivial to copy and destroy, which excludes
    /// strong, weak and unowned references; an `unowned(unsafe)` reference, an `Unmanaged` one
    /// or a raw pointer passes, and the statement promises there is none. Nil otherwise, and
    /// then each element travels through its own conformance. Specialized for a type, this folds to a
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

    /// How an array of values of this type travels as one copy of its storage: the size of a
    /// value, and the number of its values when each stored byte must be checked against it,
    /// from ``bitwiseDiscriminantCount``. Nil when the type states neither statement, or
    /// its layout does not bear the statement out, and then each element travels through its
    /// own conformance.
    @inlinable static var bitwiseTransfer: (size: Int, cases: Int?)? {
        if  let size: Int = Self.bitwiseTransferStride {
            return (size, nil)
        }
        guard
        let cases: Int = Self.bitwiseDiscriminantCount, 1 ... 256 ~= cases,
        Self.fixedTransferSize == 1,
        MemoryLayout<Self>.size == 1,
        MemoryLayout<Self>.stride == 1,
        _isPOD(Self.self) else {
            return nil
        }
        return (1, cases)
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
