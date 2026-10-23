import DistributedABI
import Synchronization

/// A case-index enumeration that states its number of discriminants and counts every read and
/// write of its own conformance: a probe, which shows that an array of them takes the checked
/// copy and calls neither.
enum Tally: UInt8, CaseIterable, Equatable, Transferable {
    case zero
    case one
    case two

    static let reads: Atomic<Int> = .init(0)
    static let writes: Atomic<Int> = .init(0)

    static var bitwiseDiscriminantCount: Int? { 3 }

    func transfer(into output: inout TransferWriter) {
        Self.writes.add(1, ordering: .relaxed)
        output.append(self.rawValue)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        Self.reads.add(1, ordering: .relaxed)
        let byte: UInt8 = try input.take(UInt8.self)
        guard
        let value: Self = .init(rawValue: byte) else {
            throw .init(.discriminant(.init(byte)))
        }
        self = value
    }
}

/// The same probe with no statement, whose every element goes through its conformance: the
/// reference that shows the probe counts.
enum UnstatedTally: UInt8, CaseIterable, Equatable, Transferable {
    case zero
    case one
    case two

    static let reads: Atomic<Int> = .init(0)
    static let writes: Atomic<Int> = .init(0)

    func transfer(into output: inout TransferWriter) {
        Self.writes.add(1, ordering: .relaxed)
        output.append(self.rawValue)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        Self.reads.add(1, ordering: .relaxed)
        let byte: UInt8 = try input.take(UInt8.self)
        guard
        let value: Self = .init(rawValue: byte) else {
            throw .init(.discriminant(.init(byte)))
        }
        self = value
    }
}
