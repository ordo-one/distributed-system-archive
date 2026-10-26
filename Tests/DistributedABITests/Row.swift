import DistributedABI

/// A value whose bytes are its wire form and whose length varies, as a serialized message is.
/// It refuses empty bytes with an error of its own, which the transport must carry unchanged.
struct Row: Equatable, ContiguousTransferable {
    let bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}
extension Row {
    func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result {
        try body(self.bytes.span.bytes)
    }
    init(transferBytes: RawSpan) throws(TransferError) {
        guard transferBytes.byteCount > 0 else {
            throw .payload(Refusal.empty)
        }
        self.init(bytes: transferBytes.withUnsafeBytes { [UInt8].init($0) })
    }
}
