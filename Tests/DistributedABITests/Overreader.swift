import DistributedABI

/// A value that states a fixed size of one byte but reads two, as a faulty conformer might: a
/// collection must refuse it, rather than read every later element from the wrong offset.
struct Overreader: Hashable, Transferable {
    let byte: UInt8

    init(byte: UInt8) {
        self.byte = byte
    }
}
extension Overreader {
    static var fixedTransferSize: Int? { 1 }
    var transferSize: Int { 1 }

    func transfer(into output: inout TransferWriter) {
        output.append(self.byte)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        let byte: UInt8 = try input.take(UInt8.self)
        _ = try input.take(UInt8.self)
        self.init(byte: byte)
    }
}
