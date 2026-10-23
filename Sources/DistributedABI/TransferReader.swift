/// A borrowed cursor over the bytes of a frame, from which each value reads its own bytes in
/// turn.
///
/// The reader cannot outlive the buffer, page or array whose bytes it reads, and neither can
/// the spans it hands out; a value that keeps bytes copies them. Every method that runs out of
/// bytes, or meets a malformed number, throws instead of trapping.
@frozen public struct TransferReader: ~Copyable, ~Escapable {
    @usableFromInline let bytes: RawSpan
    @usableFromInline var index: Int

    @_lifetime(copy bytes)
    @inlinable public init(_ bytes: RawSpan) {
        self.bytes = bytes
        self.index = 0
    }
}
extension TransferReader {
    /// The number of bytes not yet read.
    @inlinable public var remaining: Int { self.bytes.byteCount - self.index }

    /// The next `count` bytes.
    @_lifetime(copy self)
    @inlinable public mutating func take(_ count: Int) throws(TransferError) -> RawSpan {
        guard count >= 0, count <= self.remaining else {
            throw .init(.expected(count, encountered: self.remaining))
        }
        let span: RawSpan = self.bytes.extracting(self.index ..< self.index + count)
        self.index += count
        return span
    }

    /// The next `count` bytes, which the caller has found the bytes remaining hold, as a count
    /// read through ``takeCount(of:)`` for elements of a fixed size does. Always inlined, so
    /// that the read of a collection’s elements with one copy takes them inline.
    @_lifetime(copy self)
    @inlinable @inline(always) mutating func take(holding count: Int) -> RawSpan {
        // cannot overflow, since `count` fits in the bytes remaining
        let span: RawSpan = self.bytes.extracting(self.index ..< self.index &+ count)
        self.index &+= count
        return span
    }

    /// Every byte not yet read.
    @_lifetime(copy self)
    @inlinable public mutating func takeRemaining() -> RawSpan {
        let span: RawSpan = self.bytes.extracting(self.index...)
        self.index = self.bytes.byteCount
        return span
    }

    /// A ULEB128 length, then that many bytes. Always inlined, with a length of one or two
    /// bytes read inline, as the length of a serialized message of up to 16,383 bytes is, and
    /// the bytes taken inline rather than through ``take(_:)``, which a client calls out of
    /// line. Left to the optimizer, a client calls this through the framework’s stub, and a
    /// conformance whose read calls it is then reached through the protocol’s dispatch thunk
    /// rather than inlined.
    @_lifetime(copy self)
    @inlinable @inline(always) public mutating func takePrefixed() throws(TransferError) -> RawSpan {
        let length: Int = try self.takeULEB128Short()
        guard length <= self.remaining else {
            throw .init(.count(length, remaining: self.remaining))
        }
        // cannot overflow, since `length` fits in the bytes remaining
        let span: RawSpan = self.bytes.extracting(self.index ..< self.index &+ length)
        self.index &+= length
        return span
    }

    /// The bytes of a contiguous value of variable size, as ``takePrefixed()`` reads them, but
    /// emitted into the client and kept out of line. The read around it is then small enough
    /// for a client to inline into its caller, which calls the type’s open directly. With the
    /// length read inline, the read was too large to inline, and stayed a function of its own,
    /// which the optimizer merged across types and reached through a thunk per type.
    @_lifetime(copy self)
    @usableFromInline @_alwaysEmitIntoClient @inline(never) mutating func takeContiguous() throws(TransferError) -> RawSpan {
        try self.takePrefixed()
    }

    /// The bytes of a string: a ULEB128 length, then that many bytes, with only a length of
    /// one byte read inline, as the length of a short string is. Always inlined, as
    /// ``takePrefixed()`` is, but smaller, so that a client still inlines the whole string
    /// read into a collection’s element loop; with the two-byte read of ``takePrefixed()``, a
    /// string batch read a fifth more instructions.
    @_lifetime(copy self)
    @inlinable @inline(always) mutating func takeUTF8() throws(TransferError) -> RawSpan {
        let length: Int = try self.takeULEB128()
        guard length <= self.remaining else {
            throw .init(.count(length, remaining: self.remaining))
        }
        return try self.take(length)
    }

    /// A ULEB128 count of elements, refused when it exceeds the bytes remaining: every element
    /// takes at least one byte, so a hostile count never reserves room for more elements than
    /// the bytes present could hold. Always inlined, as ``takePrefixed()`` is.
    @inlinable @inline(always) public mutating func takeCount() throws(TransferError) -> Int {
        let count: Int = try self.takeULEB128()
        guard count <= self.remaining else {
            throw .init(.count(count, remaining: self.remaining))
        }
        return count
    }

    /// A fixed-width integer, little-endian, loaded unaligned.
    @inlinable public mutating func take<Integer>(
        _: Integer.Type
    ) throws(TransferError) -> Integer where Integer: FixedWidthInteger & ConvertibleFromBytes {
        let size: Int = MemoryLayout<Integer>.size
        guard size <= self.remaining else {
            throw .init(.expected(size, encountered: self.remaining))
        }
        let value: Integer = self.bytes.load(fromByteOffset: self.index, as: Integer.self)
        // cannot overflow, since `size` fits in the bytes remaining; wrapping, so that
        // `takeElement(_:)` can see that an integer reads exactly its size
        self.index &+= size
        return .init(littleEndian: value)
    }

    /// One value as the element of a collection, read through its
    /// ``Transferable/init(transferring:)``, whose errors propagate unchanged.
    ///
    /// Once that initializer has succeeded, a value whose type states a
    /// ``Transferable/fixedTransferSize`` must have consumed exactly that many bytes, or the
    /// read is refused with ``TransferError/Kind/expected(_:encountered:)``, carrying the fixed
    /// size and then the number of bytes the value consumed: a faulty conformer that read fewer
    /// or more would otherwise shift every element after it, with nothing around the element
    /// to catch it. The check follows the read rather than bounding it, so a `UInt32` read
    /// from two bytes throws its own `.expected(4, encountered: 2)`, having consumed nothing.
    ///
    /// A collection of one’s own reads each of its elements, or each key and each value of an
    /// entry, through this rather than through the element’s own initializer.
    @inlinable public mutating func takeElement<Element>(
        _: Element.Type
    ) throws(TransferError) -> Element where Element: Transferable {
        guard
        let size: Int = Element.fixedTransferSize else {
            return try .init(transferring: &self)
        }
        let start: Int = self.index
        let value: Element = try .init(transferring: &self)
        guard self.index &- start == size else {
            throw .init(.expected(size, encountered: self.index &- start))
        }
        return value
    }

    /// Reads `count` elements into `output`, each as ``takeElement(_:)`` reads it: the
    /// elements of an array’s wire form, with no count in front of them.
    ///
    /// When the element type states ``Transferable/isBitwiseTransferable`` or
    /// ``Transferable/bitwiseDiscriminantCount``, its fixed size is the size and the stride of
    /// its memory, which holds no reference, and the bytes remaining
    /// hold all `count` elements, their bytes are copied into `output` at once, each byte of a
    /// type that states a number of discriminants checked where it lies first; otherwise each
    /// element reads itself. Either way, the bytes are refused exactly where a read of one
    /// element at a time refuses them, with the same error and the reader at the same
    /// position. `output` must have room for `count` more elements. When this throws, `output`
    /// may hold some of the elements read before the error.
    ///
    /// A collection of one’s own whose elements lie in contiguous storage reads its count
    /// through ``takeCount(of:)``, which refuses a count the bytes remaining could not hold,
    /// and then its elements through this into that storage, which it initializes through an
    /// `OutputSpan`, such as the one `Array.append(addingCapacity:initializingWith:)` lends.
    @inlinable public mutating func takeElements<Element>(
        _ count: Int,
        into output: inout OutputSpan<Element>
    ) throws(TransferError) where Element: Transferable {
        precondition(0 ... output.freeCapacity ~= count, "OutputSpan capacity overflow")
        // cannot overflow, since that many elements fit in the output’s memory at that stride
        if  count != 0, case let (size, cases)? = Element.bitwiseTransfer, count &* size <= self.remaining {
            if  let cases: Int {
                try self.checkDiscriminants(count, below: cases)
            }
            output.append(bitwise: self.take(holding: count &* size), count: count)
            return
        }
        // one at a time, which also refuses a run of elements cut short where the element
        // that runs out of bytes refuses it
        for _: Int in 0 ..< count {
            output.append(try self.takeElement(Element.self))
        }
    }

    /// Refuses the input unless every byte has been read.
    @inlinable public func finish() throws(TransferError) {
        guard self.index == self.bytes.byteCount else {
            throw .init(.expected(0, encountered: self.remaining))
        }
    }
}
extension TransferReader {
    /// A ULEB128 number in canonical form: one that ends early, runs past 64 bits, carries a
    /// redundant final zero byte, or exceeds `Int.max` is refused. A number below 128, which
    /// is every length and count up to 127, takes one byte and is read inline.
    @inlinable @inline(always) mutating func takeULEB128() throws(TransferError) -> Int {
        if  self.index < self.bytes.byteCount {
            let byte: UInt8 = self.bytes.load(fromByteOffset: self.index, as: UInt8.self)
            if  byte < 0x80 {
                self.index += 1
                return Int.init(byte)
            }
        }
        return try self.takeULEB128Multibyte()
    }

    /// A ULEB128 number as ``takeULEB128()`` reads it, with a number below 16,384, which takes
    /// two bytes, read inline as well.
    @inlinable @inline(always) mutating func takeULEB128Short() throws(TransferError) -> Int {
        // cannot overflow, since the index is at most the byte count
        if  self.index &+ 1 < self.bytes.byteCount {
            let low: UInt8 = self.bytes.load(fromByteOffset: self.index, as: UInt8.self)
            if  low < 0x80 {
                self.index &+= 1
                return Int.init(low)
            }
            let high: UInt8 = self.bytes.load(fromByteOffset: self.index &+ 1, as: UInt8.self)
            // a final zero byte is redundant, and the out-of-line read refuses it
            if  high < 0x80, high != 0 {
                self.index &+= 2
                return Int.init(low & 0x7f) | Int.init(high) &<< 7
            }
        }
        return try self.takeULEB128()
    }

    // emitted into the client and kept out of line, as `TransferWriter.append(multibyte:)` is
    @usableFromInline @_alwaysEmitIntoClient @inline(never) mutating func takeULEB128Multibyte() throws(TransferError) -> Int {
        var value: UInt = 0
        var shift: Int = 0
        while true {
            guard self.index < self.bytes.byteCount else {
                throw .init(.expected(1, encountered: 0))
            }
            let byte: UInt8 = self.bytes.load(fromByteOffset: self.index, as: UInt8.self)
            self.index += 1

            let bits: UInt = .init(byte & 0x7f)
            guard shift < UInt.bitWidth, (bits &<< shift) &>> shift == bits else {
                throw .init(.malformed(remaining: self.remaining))
            }
            value |= bits &<< shift

            if  byte & 0x80 == 0 {
                guard byte != 0 || shift == 0 else {
                    throw .init(.malformed(remaining: self.remaining))
                }
                break
            }
            shift += 7
        }
        guard
        let value: Int = .init(exactly: value) else {
            throw .init(.malformed(remaining: self.remaining))
        }
        return value
    }
}
extension TransferReader {
    /// A ULEB128 count of elements of one type, as an array writes it, refused with
    /// ``TransferError/Kind/count(_:remaining:)`` when that many elements cannot fit in the
    /// bytes remaining: one byte each at least, and their fixed size each when their type
    /// states one. A collection of one’s own reads its count through this before it reserves
    /// room for its elements, so that a hostile count never reserves room for more elements
    /// than the bytes present could hold, and then reads each element through
    /// ``takeElement(_:)``.
    @inlinable public mutating func takeCount<Element>(
        of _: Element.Type
    ) throws(TransferError) -> Int where Element: Transferable {
        let count: Int = try self.takeCount()
        if  let size: Int = Element.fixedTransferSize, size > 0, count > self.remaining / size {
            throw .init(.count(count, remaining: self.remaining))
        }
        return count
    }

    /// A ULEB128 count of entries, as a dictionary writes it, refused with
    /// ``TransferError/Kind/count(_:remaining:)`` when that many entries cannot fit in the
    /// bytes remaining: a key and a value each take one byte at least, and their fixed size
    /// each when their type states one. An entry whose size overflows `Int` cannot fit either,
    /// and a count of zero is never refused, since it has no entry to fit. A keyed collection
    /// of one’s own reads its count through this before it reserves room for its entries, and
    /// then reads each key and its value through ``takeElement(_:)``.
    @inlinable public mutating func takeCount<Key, Value>(
        keys _: Key.Type,
        values _: Value.Type
    ) throws(TransferError) -> Int where Key: Transferable, Value: Transferable {
        let count: Int = try self.takeCount()
        if  count == 0 {
            return 0
        }
        let size: (partialValue: Int, overflow: Bool) = (Key.fixedTransferSize ?? 1)
            .addingReportingOverflow(Value.fixedTransferSize ?? 1)
        if  size.overflow || size.partialValue > 1 && count > self.remaining / size.partialValue {
            throw .init(.count(count, remaining: self.remaining))
        }
        return count
    }
}
