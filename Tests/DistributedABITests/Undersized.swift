import DistributedABI

/// A value that states a fixed size of two bytes but reads one, as a faulty conformer might:
/// a debug build stops at it, rather than read every later element from the wrong offset.
struct Undersized: Hashable, Transferable {
    let byte: UInt8

    init(byte: UInt8) {
        self.byte = byte
    }
}
extension Undersized {
    static var transferLayout: TransferLayout? { .fixed(size: 2) }
    var transferSize: Int { 2 }

    func transfer(into output: inout TransferWriter) {
        output.append(self.byte)
        output.append(0)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(byte: try input.take(UInt8.self))
    }
}
