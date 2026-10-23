import DistributedABI

/// An enumeration with no payload and implicit raw values, its case indices, which states its
/// case count: an array of them travels as one copy of its storage, each byte checked.
enum Mark: UInt8, CaseIterable, Equatable, Transferable {
    case none
    case near
    case at

    static var bitwiseDiscriminantCount: Int? { 3 }
}

/// The same enumeration with no statement, read one element at a time: the reference the
/// checked copy is compared against.
enum UnstatedMark: UInt8, CaseIterable, Equatable, Transferable {
    case none
    case near
    case at
}

/// A wrapper of eight bytes that states a case count, which only a one-byte type can bear out:
/// an array of them travels one element at a time.
struct WideMark: Equatable, RawRepresentable, Transferable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    static var bitwiseDiscriminantCount: Int? { 2 }
}

/// `Bool`’s wire form under a type that states no number of discriminants, read one element at
/// a time: the reference the checked copy of `Bool` is compared against.
struct UnstatedFlag: Equatable, Transferable {
    let value: Bool

    static var fixedTransferSize: Int? { 1 }
    var transferSize: Int { 1 }

    func transfer(into output: inout TransferWriter) {
        self.value.transfer(into: &output)
    }
    init(_ value: Bool) {
        self.value = value
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.value = try .init(transferring: &input)
    }
}
