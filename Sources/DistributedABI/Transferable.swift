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
    /// What every value of this type has in common on the wire, when all of them take the same
    /// number of bytes, and so how a collection moves a run of them; nil, the default, for a
    /// type whose values vary in size.
    ///
    /// A ``TransferLayout/fixed(size:)`` type is moved one value at a time, a
    /// ``TransferLayout/bitwise(size:)`` type as one copy of the storage of a run of values,
    /// and a ``TransferLayout/discriminant(count:)`` type as one copy with every byte checked.
    /// A collection of values of any of the three sizes itself from its count alone.
    ///
    /// This is a requirement rather than a marker protocol because the generic conformances of
    /// the collections make the choice: through the witness table, a requirement is one call
    /// and folds away when specialized, where asking for a protocol is a dynamic cast per
    /// collection; and the `@Transferable` macro planned for plugin-to-plugin calls states the
    /// layout of a composite by computing it from its fields’ own layouts and their
    /// `MemoryLayout`, which a conformance to a protocol cannot depend on.
    static var transferLayout: TransferLayout? { get }

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
    @inlinable public static var transferLayout: TransferLayout? { nil }
}
extension Transferable {
    /// How an array of values of this type travels as one copy of its storage: the size of a
    /// value, and the number of its values when each stored byte must be checked against it.
    /// Nil when the type’s ``transferLayout`` is neither ``TransferLayout/bitwise(size:)`` nor
    /// ``TransferLayout/discriminant(count:)``, or its memory does not bear the layout out:
    /// the size must be the size and the stride of its memory, which must be trivial to copy
    /// and destroy, excluding strong, weak and unowned references (an `unowned(unsafe)`
    /// reference, an `Unmanaged` one or a raw pointer passes, and the layout promises there is
    /// none), and a discriminant’s count must be from 1 to 256. Each element then travels
    /// through its own conformance. Specialized for a type, this folds to a constant; through
    /// the witness table, it asks the type once per collection.
    @inlinable static var bitwiseTransfer: (size: Int, cases: Int?)? {
        switch Self.transferLayout {
        case .bitwise(size: let size)?:
            guard
            size == MemoryLayout<Self>.size,
            size == MemoryLayout<Self>.stride,
            _isPOD(Self.self) else {
                return nil
            }
            return (size, nil)
        case .discriminant(count: let count)?:
            guard 1 ... 256 ~= count,
            MemoryLayout<Self>.size == 1,
            MemoryLayout<Self>.stride == 1,
            _isPOD(Self.self) else {
                return nil
            }
            return (1, count)
        case .fixed?, nil:
            return nil
        }
    }
}
extension Transferable
    where Self: FixedWidthInteger & BitwiseCopyable & ConvertibleFromBytes & ConvertibleToBytes {
    /// An integer travels as its fixed-width little-endian bytes, which on a little-endian host
    /// are the bytes it is stored as. A type that gives itself another wire form than this
    /// states another layout.
    @inlinable public static var transferLayout: TransferLayout? {
        #if _endian(little)
        .bitwise(size: MemoryLayout<Self>.size)
        #else
        .fixed(size: MemoryLayout<Self>.size)
        #endif
    }
    @inlinable public var transferSize: Int { MemoryLayout<Self>.size }

    @inlinable public func transfer(into output: inout TransferWriter) {
        output.append(littleEndian: self)
    }
    @inlinable public init(transferring input: inout TransferReader) throws(TransferError) {
        self = try input.read(littleEndian: Self.self)
    }
}
extension Transferable where Self: RawRepresentable,
    RawValue: Transferable & FixedWidthInteger {
    /// A value with an integer raw value travels as its raw value, at its raw value’s size, one
    /// value at a time: an enumeration is stored as its case index, not its raw value, so its
    /// layout is never ``TransferLayout/bitwise(size:)``. A raw value with no case is a
    /// ``TransferError/Kind/invalidDiscriminant(_:)`` error.
    @inlinable public static var transferLayout: TransferLayout? {
        RawValue.transferLayout.map { .fixed(size: $0.size) }
    }
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
            throw .init(.invalidDiscriminant(bits & mask))
        }
        self = value
    }
}
