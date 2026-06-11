@available(*, deprecated) extension Substring: Transferable {}
extension Substring: BufferEncodable {
    @inlinable public func encode(to output: inout BufferEncoder) {
        if  self.isEmpty {
            String.BinaryFormat.none.encode(to: &output)
            return
        }

        // Native strings are always contiguous, so this fast path covers
        // virtually every string encountered in practice. It performs the
        // format choice in a single bounds-check-free scan and copies the
        // UTF-8 code units in one bulk append.
        let contiguous: Void? = self.utf8.withContiguousStorageIfAvailable {
            // the `compact` format is only allowed for strings of up to
            // `compactLimit` UTF-8 code units containing no null bytes
            if  $0.count <= String.BinaryFormat.compactLimit, !$0.contains(0) {
                output.reserve(another: 2 + $0.count)
                String.BinaryFormat.compact.encode(to: &output)
                /// serializes the UTF-8 code units of a string as a c-string
                /// with a trailing null byte. The `cString` must not contain
                /// null bytes.
                output.append($0)
                output.append(0x00)
            } else {
                let header: (high: UInt8, low: UInt32) = Substring.header(size: $0.count)
                output.reserve(another: 6 + $0.count)
                String.BinaryFormat.long.encode(to: &output)
                header.low.encode(to: &output)
                header.high.encode(to: &output)
                output.append($0)
            }
        }

        if  case nil = contiguous {
            self.encode(generic: &output)
        }
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
    @usableFromInline func encode(generic output: inout BufferEncoder) {
        var format: String.BinaryFormat = .compact
        for (i, byte): (Int, UInt8) in self.utf8.enumerated() {
            guard i < String.BinaryFormat.compactLimit, byte != 0 else {
                format = .long
                break
            }
        }

        self.encode(to: &output, as: format)
    }

    @usableFromInline func encode(
        to output: inout BufferEncoder,
        as format: String.BinaryFormat
    ) {
        if  case .compact = format {
            output.reserve(another: 2 + self.utf8.count)
            format.encode(to: &output)
            /// serializes the UTF-8 code units of a string as a c-string with a trailing
            /// null byte. The `cString` must not contain null bytes.
            output.append(self.utf8)
            output.append(0x00)
        } else {
            let header: (high: UInt8, low: UInt32) = Substring.header(size: self.utf8.count)
            output.reserve(another: 6 + self.utf8.count)
            format.encode(to: &output)
            header.low.encode(to: &output)
            header.high.encode(to: &output)
            output.append(self.utf8)
        }
    }
}
extension Substring: BufferDecodable {
    @inlinable public static func decode(
        from input: inout BufferDecoder
    ) throws(BufferDecodingError) -> Self {
        try String.decode(from: &input)[...]
    }
}
