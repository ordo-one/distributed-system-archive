import DistributedABI

/// A value whose bytes are its wire form and whose length varies, as a serialized message’s
/// are, and which, unlike ``Row``, opens from no bytes at all.
struct Blob: Hashable, ContiguousTransferable {
    let bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}
extension Blob {
    func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result {
        try body(self.bytes.span.bytes)
    }
    init(transferBytes: RawSpan) throws(TransferError) {
        self.init(bytes: transferBytes.withUnsafeBytes { [UInt8].init($0) })
    }
}
extension Blob: Fuzzable {
    /// Mostly a few bytes or none, sometimes enough that the length takes two ULEB128 bytes.
    static func random(using random: inout SplitMix64, budget _: inout Int) -> Self {
        let count: Int = Int.random(in: 0 ..< 16, using: &random) == 0
            ? .random(in: 120 ... 300, using: &random)
            : .random(in: 0 ... 8, using: &random)
        return .init(bytes: (0 ..< count).map { _ in .random(in: 0 ... 0xff, using: &random) })
    }
}
