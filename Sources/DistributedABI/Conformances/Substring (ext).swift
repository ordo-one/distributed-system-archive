@available(*, deprecated) extension Substring: Transferable {}
extension Substring: BufferEncodable {
    @inlinable public func encode(to output: inout BufferEncoder) {
        var format: String.BinaryFormat
        if  self.isEmpty {
            format = .none
            format.encode(to: &output)
            return
        } else {
            format = .compact
        }

        for (i, byte): (Int, UInt8) in self.utf8.enumerated() {
            guard i < 256, byte != 0 else {
                format = .long
                break
            }
        }

        self.encode(to: &output, as: format)
    }
}
extension Substring {
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
