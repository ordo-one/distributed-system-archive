import DistributedABI
import Testing

@Suite enum Lending {
    /// A send sizes its frame, then writes into it, and a contiguous value lends its bytes once
    /// for each, wherever it lies: one that builds its bytes on every lend builds them twice
    /// per send, however deeply its containers nest. The bytes are checked as well: the value
    /// writes its own length, and no container writes another around it.
    @Test(
        arguments: [
            Shape.init("alone", lends: 2, [3, 3, 1, 4]) {
                [UInt8].init(transferring: $0)
            },
            Shape.init("optional", lends: 2, [1, 3, 3, 1, 4]) {
                [UInt8].init(transferring: $0 as Lent?)
            },
            Shape.init("nested optional", lends: 2, [1, 1, 3, 3, 1, 4]) {
                [UInt8].init(transferring: $0 as Lent??)
            },
            Shape.init("result", lends: 2, [0, 3, 3, 1, 4]) {
                [UInt8].init(transferring: Result<Lent, Failure>.success($0))
            },
            Shape.init("optional array", lends: 2, [1, 1, 3, 3, 1, 4]) {
                [UInt8].init(transferring: [$0] as [Lent]?)
            },
            Shape.init("array of 1", lends: 2, [1, 3, 3, 1, 4]) {
                [UInt8].init(transferring: [$0])
            },
            Shape.init(
                "array of 100",
                lends: 200,
                [100] + [[UInt8]].init(repeating: [3, 3, 1, 4], count: 100).joined()
            ) {
                [UInt8].init(transferring: [Lent].init(repeating: $0, count: 100))
            },
            Shape.init("array slice", lends: 2, [1, 3, 3, 1, 4]) {
                [UInt8].init(transferring: [$0][...])
            },
            Shape.init("set", lends: 2, [1, 3, 3, 1, 4]) {
                [UInt8].init(transferring: [$0] as Set<Lent>)
            },
            Shape.init("dictionary value", lends: 2, [1, 7, 3, 3, 1, 4]) {
                [UInt8].init(transferring: [7: $0] as [UInt8: Lent])
            },
            Shape.init("array of optionals", lends: 2, [2, 1, 3, 3, 1, 4, 0]) {
                [UInt8].init(transferring: [$0, nil] as [Lent?])
            },
            Shape.init("array of results", lends: 2, [2, 0, 3, 3, 1, 4, 1, 2, 0, 0, 0]) {
                [UInt8].init(
                    transferring: [.success($0), .failure(.init(code: 2))]
                    as [Result<Lent, Failure>]
                )
            },
            Shape.init("array of arrays", lends: 2, [1, 1, 3, 3, 1, 4]) {
                [UInt8].init(transferring: [[$0]] as [[Lent]])
            },
            Shape.init("dictionary of arrays", lends: 2, [1, 7, 1, 3, 3, 1, 4]) {
                [UInt8].init(transferring: [7: [$0]] as [UInt8: [Lent]])
            },
        ]
    ) static func Sends(_ shape: Shape) {
        let value: Lent = .init(bytes: [3, 1, 4])
        #expect(shape.send(value) == shape.golden)
        #expect(value.lends.count.load(ordering: .relaxed) == shape.lends)
    }
}
