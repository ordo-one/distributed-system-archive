import Testing

extension Lending {
    /// A way to send a ``Lent`` value, with the number of lends the send makes and the bytes
    /// it writes, both written out rather than derived from the library.
    struct Shape: Sendable {
        let name: String
        let lends: Int
        let golden: [UInt8]
        let send: @Sendable (Lent) -> [UInt8]

        init(
            _ name: String,
            lends: Int,
            _ golden: [UInt8],
            send: @escaping @Sendable (Lent) -> [UInt8]
        ) {
            self.name = name
            self.lends = lends
            self.golden = golden
            self.send = send
        }
    }
}
extension Lending.Shape: CustomTestStringConvertible {
    var testDescription: String { self.name }
}
