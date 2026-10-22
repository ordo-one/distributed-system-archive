import DistributedABI

extension [UInt8] {
    /// The bytes `body` writes into a region of `capacity` bytes. Writing more than the
    /// capacity traps on the output span’s capacity check.
    init(capacity: Int, writing body: (inout OutputRawSpan) -> Void) {
        self = .init(unsafeUninitializedCapacity: capacity) {
            let buffer: UnsafeMutableRawBufferPointer = .init($0)
            var output: OutputRawSpan = .init(buffer: buffer, initializedCount: 0)
            body(&output)
            $1 = output.finalize(for: buffer)
        }
    }

    /// The bytes `value` writes, in a region sized from its ``Transferable/transferSize``; a
    /// value that writes fewer than it states yields a shorter array.
    init(transferring value: some Transferable) {
        self.init(capacity: value.transferSize) { value.transfer(into: &$0) }
    }

    /// The bytes `value` writes as the part of a container.
    init(framing value: some Transferable) {
        self.init(capacity: value.framedTransferSize) { $0.append(framed: value) }
    }
}
