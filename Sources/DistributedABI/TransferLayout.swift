/// What every value of a type has in common on the wire when all of them take the same number
/// of bytes, and so how a collection moves a run of them: one value at a time, as one copy of
/// their storage, or as one copy of their storage with every byte checked.
///
/// A type states its layout in ``Transferable/transferLayout``, and a type whose values vary in
/// size states none. The three cases leave no room for a statement that contradicts itself: a
/// discriminant is one byte, and a value copied as it is stored has a size.
@frozen public enum TransferLayout: Sendable, Hashable {
    /// Every value takes `size` bytes, at least one, and a collection writes and reads each
    /// of them through its own conformance.
    ///
    /// A collection of such values sizes itself from its count alone, so the conformance must
    /// read exactly `size` bytes in ``Transferable/init(transferring:)``, which a debug build
    /// of the reader checks. A value with an integer raw value travels with its raw value’s
    /// size at this layout, never ``bitwise(size:)``, because an enumeration is stored as its
    /// case index rather than its raw value.
    case fixed(size: Int)

    /// Every value takes `size` bytes and is stored in memory exactly as them, and every bit
    /// pattern of that size is a value, so that a collection writes and reads a run of them
    /// as one copy of its storage, with the bytes on the wire unchanged.
    ///
    /// The fixed-width integers state this on a little-endian host, as do `Float` and `Double`,
    /// whose wire form is their bit pattern; on a big-endian host they state
    /// ``fixed(size:)``. A type that wraps one of them as its only stored property, and travels
    /// as it does, forwards the wrapped type’s layout in one line:
    ///
    /// ```swift
    /// @inlinable public static var transferLayout: TransferLayout? { RawValue.transferLayout }
    /// ```
    ///
    /// The collection checks that `size` is the size and the stride of the type’s memory, and
    /// that the memory is trivial to copy and destroy, which excludes strong, weak and unowned
    /// references, and moves each value through its own conformance when any of them fails.
    /// An `unowned(unsafe)` reference, an `Unmanaged` one or a raw pointer is plain bits to
    /// that check, so a type that states this must hold none of them, which is the conformer’s
    /// guarantee.
    case bitwise(size: Int)

    /// Every value takes one byte, stored in memory as the byte it travels as, and the bytes
    /// below `count` are its values, so that a collection writes a run of them as one copy of
    /// its storage and reads it back with one copy after checking every byte where it lies.
    ///
    /// `Bool` states 2. An enumeration with no payload is stored as its case index, which
    /// Swift’s type layout makes the cases’ declaration order, in one byte for two to 256
    /// cases; when its raw values are of a one-byte integer type (`UInt8`, or `Int8` below 128)
    /// and are exactly those indices, its stored byte is its transfer byte, and it can state its
    /// case count.
    ///
    /// The statement is not meant to be written by hand. A code generator or a derive macro
    /// emits it after checking from the declaration that the enumeration has no payload and that
    /// its raw values are implicit or exactly its case indices, and counting the cases: for five
    /// such cases, the conformance it generates states `.discriminant(count: 5)`.
    ///
    /// A statement written by hand must guarantee the same: a type stored in one byte, each
    /// value stored as the byte it travels as, and every byte below the count a value. The
    /// collection checks that the type’s memory is one byte, its stride one and the count from
    /// 1 to 256, and moves each value through its own conformance when any of them fails; it
    /// refuses the first byte at or above the count with the
    /// ``TransferError/Kind/invalidDiscriminant(_:)`` error a read of one value at a time
    /// reports, and leaves the reader just past it, where that read leaves it. It cannot check
    /// the rest, and nothing reports a wrong statement: a byte out of range is refused only
    /// from the stated count up, so a count above the number of cases accepts a byte of no
    /// case as a value of the type, and a count or raw values that do not match the cases read
    /// a byte as the wrong case, silently.
    case discriminant(count: Int)
}
extension TransferLayout {
    /// The number of bytes every value takes on the wire.
    @inlinable public var size: Int {
        switch self {
        case .fixed(size: let size): size
        case .bitwise(size: let size): size
        case .discriminant: 1
        }
    }
}
