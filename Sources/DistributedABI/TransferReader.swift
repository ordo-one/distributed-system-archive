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
    @inlinable public mutating func readBytes(count: Int) throws(TransferError) -> RawSpan {
        guard count >= 0, count <= self.remaining else {
            throw .init(.truncated(needed: count, remaining: self.remaining))
        }
        let span: RawSpan = self.bytes.extracting(self.index ..< self.index + count)
        self.index += count
        return span
    }

    /// The next `count` bytes, which the caller has found the bytes remaining hold, as a count
    /// read through ``readCount(of:)`` for elements whose type states a layout does. Always
    /// inlined, so that the read of a collection’s elements with one copy takes them inline.
    @_lifetime(copy self)
    @inlinable @inline(always) mutating func readBytes(holding count: Int) -> RawSpan {
        // cannot overflow, since `count` fits in the bytes remaining
        let span: RawSpan = self.bytes.extracting(self.index ..< self.index &+ count)
        self.index &+= count
        return span
    }

    /// Every byte not yet read.
    @_lifetime(copy self)
    @inlinable public mutating func readRemainingBytes() -> RawSpan {
        let span: RawSpan = self.bytes.extracting(self.index...)
        self.index = self.bytes.byteCount
        return span
    }

    /// A ULEB128 length, then that many bytes: the inverse of
    /// ``TransferWriter/append(prefixed:)``. Always inlined, with a length of one or two bytes
    /// read inline, as the length of a serialized message of up to 16,383 bytes is, and the
    /// bytes taken inline rather than through ``readBytes(count:)``, which a client calls out of
    /// line. Left to the optimizer, a client calls this through the framework’s stub, and a
    /// conformance whose read calls it is then reached through the protocol’s dispatch thunk
    /// rather than inlined.
    @_lifetime(copy self)
    @inlinable @inline(always) public mutating func readPrefixedBytes() throws(TransferError) -> RawSpan {
        let length: Int = try self.readULEB128Short()
        guard length <= self.remaining else {
            throw .init(.excessiveCount(length, remaining: self.remaining))
        }
        // cannot overflow, since `length` fits in the bytes remaining
        let span: RawSpan = self.bytes.extracting(self.index ..< self.index &+ length)
        self.index &+= length
        return span
    }

    /// The bytes of a contiguous value of variable size, as ``readPrefixedBytes()`` reads them, but
    /// emitted into the client and kept out of line. The read around it is then small enough
    /// for a client to inline into its caller, which calls the type’s open directly. With the
    /// length read inline, the read was too large to inline, and stayed a function of its own,
    /// which the optimizer merged across types and reached through a thunk per type.
    @_lifetime(copy self)
    @usableFromInline @_alwaysEmitIntoClient @inline(never) mutating func readContiguousBytes() throws(TransferError) -> RawSpan {
        try self.readPrefixedBytes()
    }

    /// The bytes of a string: a ULEB128 length, then that many bytes, with only a length of
    /// one byte read inline, as the length of a short string is. Always inlined, as
    /// ``readPrefixedBytes()`` is, but smaller, so that a client still inlines the whole string
    /// read into a collection’s element loop; with the two-byte read of
    /// ``readPrefixedBytes()``, a string batch read a fifth more instructions.
    @_lifetime(copy self)
    @inlinable @inline(always) mutating func readUTF8Bytes() throws(TransferError) -> RawSpan {
        let length: Int = try self.readULEB128()
        guard length <= self.remaining else {
            throw .init(.excessiveCount(length, remaining: self.remaining))
        }
        return try self.readBytes(count: length)
    }

    /// A ULEB128 count of elements, refused when it exceeds the bytes remaining: every element
    /// takes at least one byte, so a hostile count never reserves room for more elements than
    /// the bytes present could hold. Always inlined, as ``readPrefixedBytes()`` is.
    @inlinable @inline(always) public mutating func readCount() throws(TransferError) -> Int {
        let count: Int = try self.readULEB128()
        guard count <= self.remaining else {
            throw .init(.excessiveCount(count, remaining: self.remaining))
        }
        return count
    }

    /// One byte: a discriminant, such as the tag of an optional or a `Bool`, or a byte of
    /// another value’s own.
    @inlinable public mutating func readByte() throws(TransferError) -> UInt8 {
        guard self.index < self.bytes.byteCount else {
            throw .init(.truncated(needed: 1, remaining: 0))
        }
        let byte: UInt8 = self.bytes.load(fromByteOffset: self.index, as: UInt8.self)
        self.index &+= 1
        return byte
    }

    /// A fixed-width integer, little-endian, loaded unaligned: the inverse of
    /// ``TransferWriter/append(littleEndian:)``, and the read the integers’ own conformances
    /// make, where ``read(_:)`` would call back into them.
    @inlinable public mutating func read<Integer>(
        littleEndian _: Integer.Type
    ) throws(TransferError) -> Integer where Integer: FixedWidthInteger & ConvertibleFromBytes {
        let size: Int = MemoryLayout<Integer>.size
        guard size <= self.remaining else {
            throw .init(.truncated(needed: size, remaining: self.remaining))
        }
        let value: Integer = self.bytes.load(fromByteOffset: self.index, as: Integer.self)
        // cannot overflow, since `size` fits in the bytes remaining; wrapping, so that
        // `read(_:)` can see that an integer reads exactly its size
        self.index &+= size
        return .init(littleEndian: value)
    }

    /// One value, read through its ``Transferable/init(transferring:)``, whose errors propagate
    /// unchanged: a field of a composite, the payload of an optional, an element of a
    /// collection.
    ///
    /// A debug build of the caller checks that a value whose type states a
    /// ``Transferable/transferLayout`` consumed exactly its size, as the writer
    /// checks that every element wrote at least one: a faulty conformer that read fewer or more
    /// would otherwise shift every element after it. The check is of the conformer, not of the
    /// bytes, since a value whose bytes run out has already thrown; a release build compiles it
    /// away, and then passes the caller’s storage for the value straight to its initializer.
    ///
    /// A composite reads each of its fields, and a collection of one’s own each of its elements
    /// or each key and each value of an entry, through this rather than through the value’s own
    /// initializer. The type can be left to inference: `let field: Field = try input.read()`.
    @inlinable public mutating func read<Element>(
        _: Element.Type = Element.self
    ) throws(TransferError) -> Element where Element: Transferable {
        let start: Int = self.index
        let value: Element = try .init(transferring: &self)
        assert(
            Element.transferLayout.map { $0.size == self.index &- start } ?? true,
            """
            \(Element.self) read \(self.index &- start) bytes, but its layout states \
            \(Element.transferLayout?.size ?? 0)
            """
        )
        return value
    }

    /// Reads `count` elements into `output`, each as ``read(_:)`` reads it: the
    /// elements of an array’s wire form, with no count in front of them.
    ///
    /// When the element type’s layout is ``TransferLayout/bitwise(size:)`` or
    /// ``TransferLayout/discriminant(count:)``, its size is the size and the stride of its
    /// memory, which holds no strong, weak or unowned reference, and the bytes remaining hold
    /// all `count` elements, their bytes are copied into `output` at once, each byte of a
    /// discriminant checked where it lies first; otherwise each element reads itself. Either
    /// way, the bytes are refused exactly where a read of one element at a time refuses them,
    /// with the same error and the reader at the same position. `output` must have room for
    /// `count` more elements. When this throws, `output` may hold some of the elements read
    /// before the error.
    ///
    /// A collection of one’s own whose elements lie in contiguous storage reads its count
    /// through ``readCount(of:)``, which refuses a count the bytes remaining could not hold,
    /// and then its elements through this into that storage, which it initializes through an
    /// `OutputSpan`, such as the one `Array.append(addingCapacity:initializingWith:)` lends.
    @inlinable public mutating func readElements<Element>(
        count: Int,
        into output: inout OutputSpan<Element>
    ) throws(TransferError) where Element: Transferable {
        precondition(0 ... output.freeCapacity ~= count, "OutputSpan capacity overflow")
        // cannot overflow, since that many elements fit in the output’s memory at that stride
        if  count != 0, case let (size, cases)? = Element.bitwiseTransfer, count &* size <= self.remaining {
            if  let cases: Int {
                try self.checkDiscriminants(count, below: cases)
            }
            output.append(bitwise: self.readBytes(holding: count &* size), count: count)
            return
        }
        // one at a time, which also refuses a run of elements cut short where the element
        // that runs out of bytes refuses it
        for _: Int in 0 ..< count {
            output.append(try self.read(Element.self))
        }
    }

    /// The end of the input: refuses it unless every byte has been read. A transport makes this
    /// read last, after the values of a frame.
    @inlinable public func readEnd() throws(TransferError) {
        guard self.index == self.bytes.byteCount else {
            throw .init(.trailingBytes(remaining: self.remaining))
        }
    }
}
extension TransferReader {
    /// A ULEB128 number in canonical form: one that ends early, runs past 64 bits, carries a
    /// redundant final zero byte, or exceeds `Int.max` is refused. A number below 128, which
    /// is every length and count up to 127, takes one byte and is read inline.
    @inlinable @inline(always) mutating func readULEB128() throws(TransferError) -> Int {
        if  self.index < self.bytes.byteCount {
            let byte: UInt8 = self.bytes.load(fromByteOffset: self.index, as: UInt8.self)
            if  byte < 0x80 {
                self.index += 1
                return Int.init(byte)
            }
        }
        return try self.readULEB128Multibyte()
    }

    /// A ULEB128 number as ``readULEB128()`` reads it, with a number below 16,384, which takes
    /// two bytes, read inline as well.
    @inlinable @inline(always) mutating func readULEB128Short() throws(TransferError) -> Int {
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
        return try self.readULEB128()
    }

    // emitted into the client and kept out of line, as `TransferWriter.append(multibyte:)` is
    @usableFromInline @_alwaysEmitIntoClient @inline(never) mutating func readULEB128Multibyte() throws(TransferError) -> Int {
        var value: UInt = 0
        var shift: Int = 0
        while true {
            guard self.index < self.bytes.byteCount else {
                throw .init(.truncated(needed: 1, remaining: 0))
            }
            let byte: UInt8 = self.bytes.load(fromByteOffset: self.index, as: UInt8.self)
            self.index += 1

            let bits: UInt = .init(byte & 0x7f)
            guard shift < UInt.bitWidth, (bits &<< shift) &>> shift == bits else {
                throw .init(.malformedULEB128(remaining: self.remaining))
            }
            value |= bits &<< shift

            if  byte & 0x80 == 0 {
                guard byte != 0 || shift == 0 else {
                    throw .init(.malformedULEB128(remaining: self.remaining))
                }
                break
            }
            shift += 7
        }
        guard
        let value: Int = .init(exactly: value) else {
            throw .init(.malformedULEB128(remaining: self.remaining))
        }
        return value
    }
}
extension TransferReader {
    /// A ULEB128 count of elements of one type, as an array writes it, refused with
    /// ``TransferError/Kind/excessiveCount(_:remaining:)`` when that many elements cannot fit
    /// in the bytes remaining: one byte each at least, and their size each when their type
    /// states a layout. A collection of one’s own reads its count through this before it
    /// reserves room for its elements, so that a hostile count never reserves room for more
    /// elements than the bytes present could hold, and then reads each element through
    /// ``read(_:)``, or all of them through ``readElements(count:into:)``.
    @inlinable public mutating func readCount<Element>(
        of _: Element.Type
    ) throws(TransferError) -> Int where Element: Transferable {
        let count: Int = try self.readCount()
        if  let size: Int = Element.transferLayout?.size, size > 0, count > self.remaining / size {
            throw .init(.excessiveCount(count, remaining: self.remaining))
        }
        return count
    }

    /// A ULEB128 count of entries, as a dictionary writes it, refused with
    /// ``TransferError/Kind/excessiveCount(_:remaining:)`` when that many entries cannot fit
    /// in the bytes remaining: a key and a value each take one byte at least, and their size each
    /// when their type states a layout. An entry whose size overflows `Int` cannot fit either,
    /// and a count of zero is never refused, since it has no entry to fit. A keyed collection
    /// of one’s own reads its count through this before it reserves room for its entries, and
    /// then reads each key and its value through ``read(_:)``.
    @inlinable public mutating func readCount<Key, Value>(
        keys _: Key.Type,
        values _: Value.Type
    ) throws(TransferError) -> Int where Key: Transferable, Value: Transferable {
        let count: Int = try self.readCount()
        if  count == 0 {
            return 0
        }
        let size: (partialValue: Int, overflow: Bool) = (Key.transferLayout?.size ?? 1)
            .addingReportingOverflow(Value.transferLayout?.size ?? 1)
        if  size.overflow || size.partialValue > 1 && count > self.remaining / size.partialValue {
            throw .init(.excessiveCount(count, remaining: self.remaining))
        }
        return count
    }
}
