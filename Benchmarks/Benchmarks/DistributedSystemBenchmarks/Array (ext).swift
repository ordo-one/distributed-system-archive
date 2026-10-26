import DistributedABI

extension [UInt8] {
    /// The bytes `value` writes, in an array allocated once at its exact size.
    @inlinable init(transferring value: some Transferable) {
        let size: Int = value.transferSize
        self = .init(unsafeUninitializedCapacity: size) {
            let buffer: UnsafeMutableRawBufferPointer = .init($0)
            var output: OutputRawSpan = .init(buffer: buffer, initializedCount: 0)
            output.withTransferWriter { value.transfer(into: &$0) }
            $1 = output.finalize(for: buffer)
        }
    }
}
