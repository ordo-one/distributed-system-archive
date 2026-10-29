import DistributedABI

/// A hand-written composite with a contiguous field, written and read field by field.
struct Envelope: Transferable {
    let tag: UInt8
    let payload: Lent

    init(tag: UInt8, payload: Lent) {
        self.tag = tag
        self.payload = payload
    }
}
extension Envelope {
    var transferSize: Int {
        self.tag.transferSize + self.payload.transferSize
    }

    func transfer(into output: inout TransferWriter) {
        self.tag.transfer(into: &output)
        self.payload.transfer(into: &output)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(tag: try .init(transferring: &input), payload: try .init(transferring: &input))
    }
}
