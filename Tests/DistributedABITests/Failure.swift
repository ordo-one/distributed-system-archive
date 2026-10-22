import DistributedABI

/// An error that travels as the failure of a `Result`.
struct Failure: Error, Equatable, Transferable {
    let code: Int32

    init(code: Int32) {
        self.code = code
    }
}
extension Failure {
    static var fixedTransferSize: Int? { Int32.fixedTransferSize }
    var transferSize: Int { self.code.transferSize }

    func transfer(into output: inout OutputRawSpan) {
        self.code.transfer(into: &output)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(code: try .init(transferring: &input))
    }
}
