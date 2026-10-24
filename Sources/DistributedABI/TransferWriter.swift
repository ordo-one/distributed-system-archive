/// A cursor over the memory a frame reserved, into which each value writes its own bytes in
/// turn: the counterpart of ``TransferReader``.
///
/// The writer holds the `OutputRawSpan` the transport lends it, for the duration of one
/// ``Swift/OutputRawSpan/withTransferWriter(_:)``, and carries the library’s wire helpers, so
/// that they stay off the standard library’s type. Every member is `@inlinable`, and the
/// multibyte length helper is emitted into the client and kept out of line.
/// The writer owns the span while it writes, since a writer that borrowed it would have to
/// hold a pointer; taking the span in and giving it back costs a copy of its three words
/// where the transport holds it in memory, measured at a dozen instructions per write.
@frozen public struct TransferWriter: ~Copyable, ~Escapable {
    @usableFromInline var output: OutputRawSpan

    @_lifetime(copy output)
    @inlinable init(_ output: consuming OutputRawSpan) {
        self.output = output
    }
}
extension TransferWriter {
    /// Appends one byte.
    @inlinable @inline(always) public mutating func append(_ byte: UInt8) {
        self.output.append(byte)
    }

    /// Appends `bytes` with one memcpy into the reserved region.
    @inlinable public mutating func append(bytes: RawSpan) {
        let count: Int = bytes.byteCount
        precondition(count <= self.output.freeCapacity, "OutputRawSpan capacity overflow")
        // the standard library has no bulk append of a span into an `OutputRawSpan` yet, and a
        // byte-at-a-time loop is the cost this library exists to avoid; SE-0558 adds the bulk
        // updates of initialized memory and defers this append to a follow-up proposal, which
        // would make this a safe call:
        // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0558-mutablespan-bulk-updates.md
        unsafe self.output.withUnsafeMutableBytes {
            (buffer: UnsafeMutableRawBufferPointer, initialized: inout Int) in
            bytes.withUnsafeBytes {
                unsafe UnsafeMutableRawBufferPointer.init(
                    rebasing: buffer[initialized ..< initialized + count]
                ).copyMemory(from: $0)
            }
            initialized += count
        }
    }

    /// Appends `value` as a ULEB128 number. A number below 128 takes one byte and is written
    /// inline.
    @inlinable @inline(always) public mutating func append(uleb128 value: UInt) {
        if  value < 0x80 {
            self.append(UInt8.init(truncatingIfNeeded: value))
        } else {
            self.append(multibyte: value)
        }
    }

    // emitted into the client, so a number of 128 or more is a direct call rather than one
    // through the framework’s symbol stub, and kept out of line, away from every caller;
    // `@inlinable @inline(never)` was measured and still called through the stub, since a
    // non-generic body that is not inlined runs the library’s own copy
    @usableFromInline @_alwaysEmitIntoClient @inline(never) mutating func append(multibyte value: UInt) {
        var value: UInt = value
        while true {
            let byte: UInt8 = .init(truncatingIfNeeded: value & 0x7f)
            value >>= 7
            if  value == 0 {
                self.append(byte)
                return
            }
            self.append(byte | 0x80)
        }
    }

    /// Appends a fixed-width integer in little-endian byte order.
    @inlinable public mutating func append<Integer>(
        littleEndian value: Integer
    ) where Integer: FixedWidthInteger & BitwiseCopyable & ConvertibleToBytes {
        self.output.append(value.littleEndian, as: Integer.self)
    }

    /// Writes `value` as one element of a collection, through its
    /// ``Transferable/transfer(into:)``. A debug build of the caller checks that it wrote at
    /// least one byte, as every value must, here, where the type that broke the rule is still
    /// known; a release build compiles the check away. A collection of one’s own writes each
    /// of its elements, or each key and each value of an entry, through this rather than
    /// through the element’s own `transfer(into:)`.
    @inlinable @inline(always) public mutating func append<Element>(
        element value: Element
    ) where Element: Transferable {
        let start: Int = self.output.byteCount
        value.transfer(into: &self)
        assert(
            self.output.byteCount > start,
            "\(Element.self) wrote no bytes, but every value takes at least one"
        )
    }

    /// Writes `elements` one after another, each as ``append(element:)`` writes it, with no
    /// count in front of them: the elements of an array’s wire form.
    ///
    /// When the element type’s layout is ``TransferLayout/bitwise(size:)`` or
    /// ``TransferLayout/discriminant(count:)``, and its size is the size and the stride of its
    /// memory, which holds no strong, weak or unowned reference, the elements’ storage is
    /// written with one copy instead, which is the same bytes; otherwise each element writes
    /// itself. A collection of one’s own whose elements lie in contiguous storage writes its
    /// count with ``append(uleb128:)`` and then its elements through this, from a span of that
    /// storage, and reads them back with ``TransferReader/takeElements(_:into:)``.
    @inlinable public mutating func append<Element>(elements: Span<Element>) where Element: Transferable {
        if  elements.count != 0, case _? = Element.bitwiseTransfer {
            self.append(bitwise: elements)
            return
        }
        for i: Int in elements.indices {
            self.append(element: elements[i])
        }
    }

    /// Appends the storage of `elements` with one copy. The caller has found
    /// ``Transferable/bitwiseTransfer`` for the element type: the elements hold no strong, weak
    /// or unowned reference and no padding, and their storage is their transfer bytes, one
    /// after another.
    @inlinable mutating func append<Element>(bitwise elements: Span<Element>) where Element: Transferable {
        self.append(bytes: unsafe elements.bytes)
    }

    /// Appends a ULEB128 length, then `bytes`: the inverse of
    /// ``TransferReader/takePrefixed()``.
    @inlinable public mutating func append(prefixed bytes: RawSpan) {
        self.append(uleb128: UInt.init(bytes.byteCount))
        self.append(bytes: bytes)
    }
}
