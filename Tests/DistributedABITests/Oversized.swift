import DistributedABI

/// A key that states a fixed size of `Int.max` bytes, so that the least size of a dictionary
/// entry, its key’s size and its value’s, overflows: a dictionary with entries must be refused
/// rather than trap, and an empty one, which reserves room for no entry, must still read.
struct Oversized: Hashable, Transferable {
    let byte: UInt8

    init(byte: UInt8) {
        self.byte = byte
    }
}
extension Oversized {
    static var fixedTransferSize: Int? { .max }
    var transferSize: Int { 1 }

    func transfer(into output: inout TransferWriter) {
        output.append(self.byte)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(byte: try input.take(UInt8.self))
    }
}
