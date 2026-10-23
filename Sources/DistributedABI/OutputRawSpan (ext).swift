extension OutputRawSpan {
    /// Appends `bytes` with one memcpy into the reserved region.
    @inlinable public mutating func append(bytes: RawSpan) {
        let count: Int = bytes.byteCount
        precondition(count <= self.freeCapacity, "OutputRawSpan capacity overflow")
        // the standard library has no bulk append of a span into an `OutputRawSpan` yet, and a
        // byte-at-a-time loop is the cost this library exists to avoid; SE-0558 adds the bulk
        // updates of initialized memory and defers this append to a follow-up proposal, which
        // would make this a safe call:
        // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0558-mutablespan-bulk-updates.md
        unsafe self.withUnsafeMutableBytes {
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
        self.append(value.littleEndian, as: Integer.self)
    }

    /// Appends a ULEB128 length, then `bytes`: the inverse of
    /// ``TransferReader/takePrefixed()``.
    @inlinable public mutating func append(prefixed bytes: RawSpan) {
        self.append(uleb128: UInt.init(bytes.byteCount))
        self.append(bytes: bytes)
    }
}
