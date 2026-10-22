/// A borrowed cursor over the bytes of one frame, argument or element.
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

    /// Every byte not yet read.
    @_lifetime(copy self)
    @inlinable public mutating func takeRemaining() -> RawSpan {
        let span: RawSpan = self.bytes.extracting(self.index...)
        self.index = self.bytes.byteCount
        return span
    }

    /// A ULEB128 length, then that many bytes.
    @_lifetime(copy self)
    @inlinable public mutating func takePrefixed() throws(TransferError) -> RawSpan {
        let length: Int = try self.takeULEB128()
        guard length <= self.remaining else {
            throw .init(.count(length, remaining: self.remaining))
        }
        return try self.take(length)
    }

    /// A ULEB128 count of elements, refused when it exceeds the bytes remaining: every element
    /// takes at least one byte, so a hostile count never reserves more than the bytes present.
    @inlinable public mutating func takeCount() throws(TransferError) -> Int {
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
        self.index += size
        return .init(littleEndian: value)
    }

    /// One value as the part of a container, the inverse of ``OutputRawSpan/append(framed:)``:
    /// read in place when its type has a fixed size, and otherwise from exactly the bytes its
    /// ULEB128 length frames, all of which it must read.
    @inlinable public mutating func take<Value>(
        framed _: Value.Type
    ) throws(TransferError) -> Value where Value: Transferable {
        if  case nil = Value.fixedTransferSize {
            var element: TransferReader = .init(try self.takePrefixed())
            let value: Value = try .init(transferring: &element)
            try element.finish()
            return value
        } else {
            return try .init(transferring: &self)
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
    @inlinable @inline(__always) mutating func takeULEB128() throws(TransferError) -> Int {
        if  self.index < self.bytes.byteCount {
            let byte: UInt8 = self.bytes.load(fromByteOffset: self.index, as: UInt8.self)
            if  byte < 0x80 {
                self.index += 1
                return Int.init(byte)
            }
        }
        return try self.takeULEB128Multibyte()
    }

    @usableFromInline mutating func takeULEB128Multibyte() throws(TransferError) -> Int {
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
                throw .init(.count(-1, remaining: self.remaining))
            }
            value |= bits &<< shift

            if  byte & 0x80 == 0 {
                guard byte != 0 || shift == 0 else {
                    throw .init(.count(-1, remaining: self.remaining))
                }
                break
            }
            shift += 7
        }
        guard
        let value: Int = .init(exactly: value) else {
            throw .init(.count(-1, remaining: self.remaining))
        }
        return value
    }
}
extension TransferReader {
    /// A count of elements of one type, refused when the elements cannot fit in the bytes
    /// remaining: one byte each at least, and their fixed size each when they have one.
    @inlinable mutating func takeCount<Element>(
        of _: Element.Type
    ) throws(TransferError) -> Int where Element: Transferable {
        let count: Int = try self.takeCount()
        if  let size: Int = Element.fixedTransferSize, size > 0, count > self.remaining / size {
            throw .init(.count(count, remaining: self.remaining))
        }
        return count
    }
}
