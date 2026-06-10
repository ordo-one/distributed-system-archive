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
            (utf8: UnsafeBufferPointer<UInt8>) in

            // the `compact` format is only allowed for strings of up to
            // 256 UTF-8 code units containing no null bytes
            var compact: Bool = utf8.count <= 256
            if  compact {
                var i: Int = 0
                while i < utf8.count {
                    if  utf8[i] == 0 {
                        compact = false
                        break
                    }
                    i += 1
                }
            }

            if  compact {
                output.reserve(another: 2 + utf8.count)
                String.BinaryFormat.compact.encode(to: &output)
                /// serializes the UTF-8 code units of a string as a c-string
                /// with a trailing null byte. The `cString` must not contain
                /// null bytes.
                output.append(utf8)
                output.append(0x00)
            } else {
                // 1 TB ought to be enough for anyone
                let size: Int = utf8.count
                let high: UInt8 = .init(size >> 32)
                let low: UInt32 = .init(size & 0xffff_ffff)

                output.reserve(another: 6 + size)
                String.BinaryFormat.long.encode(to: &output)
                // the alignment is going to suck either way we do it, so we
                // might as well make it look aesthetically like the little
                // endian Int40 it will be most of the time
                low.encode(to: &output)
                high.encode(to: &output)
                output.append(utf8)
            }
        }

        if  case nil = contiguous {
            self.encode(generic: &output)
        }
    }
}
extension Substring {
    /// The slow path, for the rare non-contiguous (bridged) string.
    @usableFromInline func encode(generic output: inout BufferEncoder) {
        var format: String.BinaryFormat = .compact
        for (i, byte): (Int, UInt8) in self.utf8.enumerated() {
            guard i < 256, byte != 0 else {
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
            // 1 TB ought to be enough for anyone
            let size: Int = self.utf8.count
            let high: UInt8 = .init(size >> 32)
            let low: UInt32 = .init(size & 0xffff_ffff)

            output.reserve(another: 6 + size)
            format.encode(to: &output)
            // the alignment is going to suck either way we do it, so we might as
            // well make it look aesthetically like the little endian Int40 it
            // will be most of the time
            low.encode(to: &output)
            high.encode(to: &output)
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
