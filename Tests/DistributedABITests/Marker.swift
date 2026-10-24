import DistributedABI

/// A composite with no fields, which writes a zero so that it takes the one byte every value
/// must, and so reads back from inside a collection.
struct Marker: Equatable, Transferable {
    init() {
    }
}
extension Marker {
    var transferSize: Int { 1 }

    func transfer(into output: inout TransferWriter) {
        output.append(0)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        switch try input.readByte() {
        case 0: self.init()
        case let code: throw .init(.invalidDiscriminant(.init(code)))
        }
    }
}
