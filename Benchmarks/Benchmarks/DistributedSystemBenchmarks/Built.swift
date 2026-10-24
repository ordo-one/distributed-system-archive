import DistributedABI

/// A message that builds its bytes on every lend, as a value that travels as its JSON encodes
/// itself each time it lends its bytes: every lend allocates them and encodes the fields into
/// them, so the number of lends a send makes is most of its cost. Its size varies, so it writes
/// its length before its bytes wherever it travels.
struct Built {
    let fields: [UInt64]

    init(fields: [UInt64]) {
        self.fields = fields
    }
}
extension Built: Equatable {}
extension Built: ContiguousTransferable {
    func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result {
        let bytes: [UInt8] = self.build()
        return try body(bytes.span.bytes)
    }
    init(transferBytes: RawSpan) throws(TransferError) {
        var input: TransferReader = .init(transferBytes)
        let count: UInt32 = try input.read(littleEndian: UInt32.self)
        var fields: [UInt64] = []
        for _: UInt32 in 0 ..< count {
            fields.append(try input.read(littleEndian: UInt64.self))
        }
        try input.readEnd()
        self.init(fields: fields)
    }
}
extension Built {
    /// The bytes, built anew: the number of fields, then each field, little-endian.
    @inline(never) func build() -> [UInt8] {
        let size: Int = 4 + 8 * self.fields.count
        return .init(unsafeUninitializedCapacity: size) {
            let buffer: UnsafeMutableRawBufferPointer = .init($0)
            var output: OutputRawSpan = .init(buffer: buffer, initializedCount: 0)
            output.withTransferWriter {
                $0.append(littleEndian: UInt32.init(self.fields.count))
                for field: UInt64 in self.fields {
                    $0.append(littleEndian: field)
                }
            }
            $1 = output.finalize(for: buffer)
        }
    }
}
