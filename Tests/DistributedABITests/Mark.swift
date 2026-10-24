import DistributedABI

/// An enumeration with no payload and implicit raw values, its case indices, which states its
/// case count: an array of them travels as one copy of its storage, each byte checked.
enum Mark: UInt8, CaseIterable, Equatable, Transferable {
    case none
    case near
    case at

    static var transferLayout: TransferLayout? { .discriminant(count: 3) }
}

/// The same enumeration with no statement, read one element at a time: the reference the
/// checked copy is compared against.
enum UnstatedMark: UInt8, CaseIterable, Equatable, Transferable {
    case none
    case near
    case at
}

/// A value of one byte on the wire that states a discriminant layout but takes two bytes of
/// memory, which only a one-byte type can bear out: an array of them travels one element at a
/// time.
struct WideMark: Equatable, Transferable {
    let value: UInt8
    let spare: UInt8

    init(_ value: UInt8) {
        self.value = value
        self.spare = 0
    }

    static var transferLayout: TransferLayout? { .discriminant(count: 2) }
    var transferSize: Int { 1 }

    func transfer(into output: inout TransferWriter) {
        output.append(self.value)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        let byte: UInt8 = try input.readByte()
        guard byte < 2 else {
            throw .init(.invalidDiscriminant(.init(byte)))
        }
        self.init(byte)
    }
}

/// `Bool`’s wire form under a type that states no number of discriminants, read one element at
/// a time: the reference the checked copy of `Bool` is compared against.
struct UnstatedFlag: Equatable, Transferable {
    let value: Bool

    static var transferLayout: TransferLayout? { .fixed(size: 1) }
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
