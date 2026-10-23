import DistributedABI

extension [UInt8] {
    /// The bytes `body` writes into a region of `capacity` bytes. Writing more than the
    /// capacity traps on the output span’s capacity check.
    init(capacity: Int, writing body: (inout TransferWriter) -> Void) {
        self = .init(unsafeUninitializedCapacity: capacity) {
            let buffer: UnsafeMutableRawBufferPointer = .init($0)
            var output: OutputRawSpan = .init(buffer: buffer, initializedCount: 0)
            output.withTransferWriter(body)
            $1 = output.finalize(for: buffer)
        }
    }

    /// The bytes `value` writes, in a region sized from its ``Transferable/transferSize``; a
    /// value that writes fewer than it states yields a shorter array.
    init(transferring value: some Transferable) {
        self.init(capacity: value.transferSize) { value.transfer(into: &$0) }
    }
}
extension Array: Fuzzable where Element: Fuzzable {
    static var shape: Fuzz.Shape { .elements(Element.shape, ordered: true) }

    static func random(using random: inout SplitMix64, budget: inout Int) -> Self {
        let count: Int = Fuzz.count(using: &random, budget: &budget)
        return (0 ..< count).map { _ in .random(using: &random, budget: &budget) }
    }

    static func same(_ a: Self, _ b: Self) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy(Element.same(_:_:))
    }
}
