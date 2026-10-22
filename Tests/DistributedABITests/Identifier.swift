import DistributedABI

/// A value whose bytes are its wire form and whose size is fixed, as an identifier is: an
/// array of them packs with no per-element length.
struct Identifier: Equatable, Hashable, ContiguousTransferable {
    let bytes: [UInt8]

    init(bytes: [UInt8]) {
        precondition(bytes.count == 8)
        self.bytes = bytes
    }
}
extension Identifier {
    init(_ value: UInt64) {
        self.init(bytes: (0 ..< 8).map { UInt8.init(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}
extension Identifier {
    static var fixedTransferSize: Int? { 8 }

    func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result {
        try body(self.bytes.span.bytes)
    }
    /// Refuses a wrong count with an error, so a library that hands it the wrong bytes fails
    /// a test instead of trapping in ``init(bytes:)``.
    init(transferBytes: RawSpan) throws(TransferError) {
        guard transferBytes.byteCount == 8 else {
            throw .init(.expected(8, encountered: transferBytes.byteCount))
        }
        self.init(bytes: transferBytes.withUnsafeBytes { [UInt8].init($0) })
    }
}
extension Identifier: Fuzzable {
    static func random(using random: inout SplitMix64, budget _: inout Int) -> Self {
        .init(random.next())
    }
}
