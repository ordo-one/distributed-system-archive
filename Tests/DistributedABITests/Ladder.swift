import DistributedABI

/// A hand-written composite that holds an inline array, written and read field by field, and
/// states the sum of its fields’ fixed sizes, so that it keeps a fixed size of its own.
struct Ladder: Transferable {
    let prices: InlineArray<2, Int32>
    let side: Side

    init(prices: InlineArray<2, Int32>, side: Side) {
        self.prices = prices
        self.side = side
    }
}
extension Ladder {
    static var transferLayout: TransferLayout? {
        guard
        let prices: TransferLayout = InlineArray<2, Int32>.transferLayout,
        let side: TransferLayout = Side.transferLayout else {
            return nil
        }
        return .fixed(size: prices.size + side.size)
    }
    var transferSize: Int {
        self.prices.transferSize + self.side.transferSize
    }

    func transfer(into output: inout TransferWriter) {
        self.prices.transfer(into: &output)
        self.side.transfer(into: &output)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(prices: try .init(transferring: &input), side: try .init(transferring: &input))
    }
}
