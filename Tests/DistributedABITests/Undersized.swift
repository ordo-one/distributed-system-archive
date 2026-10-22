import DistributedABI

/// A value that states a fixed size of two bytes but reads one, as a faulty conformer might:
/// its container must refuse it, rather than read every later part from the wrong offset.
struct Undersized: Transferable {
    let byte: UInt8

    init(byte: UInt8) {
        self.byte = byte
    }
}
extension Undersized {
    static var fixedTransferSize: Int? { 2 }
    var transferSize: Int { 2 }

    func transfer(into output: inout OutputRawSpan) {
        output.append(self.byte)
        output.append(0)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(byte: try input.take(UInt8.self))
    }
}
