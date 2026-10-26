import DistributedABI

/// A message whose bytes are its wire form and live in an instance of a class, as the bytes of
/// an SDK message live in its storage object: every copy of the message retains and releases
/// it. Its size varies, so it writes its length before its bytes wherever it travels.
final class Message {
    let bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}
extension Message: Equatable {
    static func == (a: Message, b: Message) -> Bool { a.bytes == b.bytes }
}
extension Message: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.bytes)
    }
}
extension Message: ContiguousTransferable {
    /// Lends the stored bytes in place. Of the lends tried, this one costs what an SDK
    /// message’s lend costs: a loop over an array of messages that copies each element
    /// retains and releases it, and one that the optimizer lets borrow it does not.
    func withTransferBytes<Result>(_ body: (RawSpan) throws -> Result) rethrows -> Result {
        try self.bytes.withUnsafeBytes { try body($0.bytes) }
    }
    convenience init(transferBytes: RawSpan) throws(TransferError) {
        self.init(bytes: transferBytes.withUnsafeBytes { [UInt8].init($0) })
    }
}
