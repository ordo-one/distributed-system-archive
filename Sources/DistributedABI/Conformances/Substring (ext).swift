@available(*, deprecated) extension Substring: Transferable {}
extension Substring: BufferEncodable {
    @inlinable public func encode(into output: inout OutputRawSpan) {
        if  self.isEmpty {
            String.BinaryFormat.none.encode(into: &output)
            return
        }

        // Native strings are always contiguous, so this fast path covers
        // virtually every string encountered in practice. It performs the
        // format choice in a single bounds-check-free scan and copies the
        // UTF-8 code units in one bulk copy.
        let contiguous: Void? = self.utf8.withContiguousStorageIfAvailable {
            (utf8: UnsafeBufferPointer<UInt8>) in
            // the `compact` format is only allowed for strings of up to
            // `compactLimit` UTF-8 code units containing no null bytes
            if  utf8.count <= String.BinaryFormat.compactLimit, !utf8.contains(0) {
                String.BinaryFormat.compact.encode(into: &output)
                /// serializes the UTF-8 code units of a string as a c-string
                /// with a trailing null byte. The `cString` must not contain
                /// null bytes.
                output.append(copying: .init(utf8))
                output.append(0x00)
            } else {
                let header: (high: UInt8, low: UInt32) = Substring.header(size: utf8.count)
                String.BinaryFormat.long.encode(into: &output)
                header.low.encode(into: &output)
                header.high.encode(into: &output)
                output.append(copying: .init(utf8))
            }
        }

        if  case nil = contiguous {
            self.encode(generic: &output)
        }
    }
    @inlinable public var encodedSize: Int {
        //  Upper bound: empty -> 1 (format `.none`); otherwise reserve as if the
        //  `long` framing were used (format byte + 5-byte length + payload), which
        //  is >= the `compact` framing (format byte + payload + 1 terminator). This
        //  avoids a second compact/long scan in the size pass; `encode(into:)`
        //  writes the exact bytes.
        let count: Int = self.utf8.count
        return count == 0 ? 1 : 6 + count
    }
}
extension Substring {
    /// Splits a UTF-8 byte count into the 40-bit length header the `long` string
    /// format uses. Computed through `UInt64` so the `>> 32` is well-defined on
    /// 32-bit platforms (the bytes emitted are identical on 64-bit). The header is
    /// written little-endian as the `low` `UInt32` followed by the `high` `UInt8`.
    @usableFromInline static func header(size: Int) -> (high: UInt8, low: UInt32) {
        // 1 TB ought to be enough for anyone.
        let size: UInt64 = .init(size)
        return (high: .init(size >> 32), low: .init(truncatingIfNeeded: size))
    }

    /// The slow path, for the rare non-contiguous (bridged) string.
    @usableFromInline func encode(generic output: inout OutputRawSpan) {
        var format: String.BinaryFormat = .compact
        for (i, byte): (Int, UInt8) in self.utf8.enumerated() {
            guard i < String.BinaryFormat.compactLimit, byte != 0 else {
                format = .long
                break
            }
        }

        //  Non-contiguous: materialize the UTF-8 once so it can be bulk-copied.
        //  This rare path is the only place a string encode allocates.
        let bytes: [UInt8] = .init(self.utf8)
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if  case .compact = format {
                format.encode(into: &output)
                output.append(copying: raw)
                output.append(0x00)
            } else {
                let header: (high: UInt8, low: UInt32) = Substring.header(size: bytes.count)
                format.encode(into: &output)
                header.low.encode(into: &output)
                header.high.encode(into: &output)
                output.append(copying: raw)
            }
        }
    }
}
extension Substring: BufferDecodable {
    @inlinable public static func decode(
        from input: RawSpan,
        at index: inout Int
    ) throws(BufferDecodingError) -> Self {
        try String.decode(from: input, at: &index)[...]
    }
}
