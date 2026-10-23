import DistributedABI

/// A value whose bytes are its wire form and whose length varies, which counts the times it
/// lends them: every copy adds to the same count.
struct Lent: ContiguousTransferable {
    let bytes: [UInt8]
    let lends: Lends

    init(bytes: [UInt8], lends: Lends) {
        self.bytes = bytes
        self.lends = lends
    }
}
extension Lent {
    init(bytes: [UInt8]) {
        self.init(bytes: bytes, lends: .init())
    }
}
extension Lent: Equatable {
    static func == (a: Self, b: Self) -> Bool { a.bytes == b.bytes }
}
extension Lent: Error {
}
extension Lent: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.bytes)
    }
}
extension Lent {
    func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result {
        self.lends.count.add(1, ordering: .relaxed)
        return try body(self.bytes.span.bytes)
    }
    init(transferBytes: RawSpan) throws(TransferError) {
        self.init(bytes: transferBytes.withUnsafeBytes { [UInt8].init($0) })
    }
}
