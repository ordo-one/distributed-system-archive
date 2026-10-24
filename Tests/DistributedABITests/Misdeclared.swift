import DistributedABI

/// A composite of two `UInt32`, which states that it is stored as its transfer bytes as the
/// derive macro would: from its fields’ own statements and its layout, checked in code.
struct Pair: Equatable, Transferable {
    let low: UInt32
    let high: UInt32

    static var transferLayout: TransferLayout? {
        guard
        let low: TransferLayout = UInt32.transferLayout,
        let high: TransferLayout = UInt32.transferLayout else {
            return nil
        }
        let size: Int = low.size + high.size
        guard
        case .bitwise = low,
        case .bitwise = high,
        MemoryLayout<Self>.offset(of: \Self.low) == 0,
        MemoryLayout<Self>.offset(of: \Self.high) == low.size,
        MemoryLayout<Self>.size == size else {
            return .fixed(size: size)
        }
        return .bitwise(size: size)
    }
    var transferSize: Int { self.low.transferSize + self.high.transferSize }

    func transfer(into output: inout TransferWriter) {
        self.low.transfer(into: &output)
        self.high.transfer(into: &output)
    }
    init(low: UInt32, high: UInt32) {
        self.low = low
        self.high = high
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(low: try .init(transferring: &input), high: try .init(transferring: &input))
    }
}

/// The same composite as ``Pair`` with no statement, read one element at a time: the reference
/// its copy is compared against.
struct UnstatedPair: Equatable, Transferable {
    let low: UInt32
    let high: UInt32

    static var transferLayout: TransferLayout? { .fixed(size: 8) }
    var transferSize: Int { 8 }

    func transfer(into output: inout TransferWriter) {
        self.low.transfer(into: &output)
        self.high.transfer(into: &output)
    }
    init(low: UInt32, high: UInt32) {
        self.low = low
        self.high = high
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(low: try .init(transferring: &input), high: try .init(transferring: &input))
    }
}

/// A composite that states it is stored as its transfer bytes although it is not: nine bytes on
/// the wire, a stride of sixteen in memory. An array of them must travel one element at a time.
struct TrailingPadding: Equatable, Transferable {
    let price: Int64
    let side: UInt8

    static var transferLayout: TransferLayout? { .bitwise(size: 9) }
    var transferSize: Int { 9 }

    func transfer(into output: inout TransferWriter) {
        self.price.transfer(into: &output)
        self.side.transfer(into: &output)
    }
    init(price: Int64, side: UInt8) {
        self.price = price
        self.side = side
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(price: try .init(transferring: &input), side: try .init(transferring: &input))
    }
}

/// A composite with padding between its fields, which states that it is stored as its transfer
/// bytes in the macro’s form: its offset check fails, so it does not.
struct InteriorPadding: Equatable, Transferable {
    let side: UInt8
    let price: Int64

    static var transferLayout: TransferLayout? {
        guard
        let side: TransferLayout = UInt8.transferLayout,
        let price: TransferLayout = Int64.transferLayout else {
            return nil
        }
        let size: Int = side.size + price.size
        guard
        case .bitwise = side,
        case .bitwise = price,
        MemoryLayout<Self>.offset(of: \Self.side) == 0,
        MemoryLayout<Self>.offset(of: \Self.price) == side.size,
        MemoryLayout<Self>.size == size else {
            return .fixed(size: size)
        }
        return .bitwise(size: size)
    }
    var transferSize: Int { 9 }

    func transfer(into output: inout TransferWriter) {
        self.side.transfer(into: &output)
        self.price.transfer(into: &output)
    }
    init(side: UInt8, price: Int64) {
        self.side = side
        self.price = price
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(side: try .init(transferring: &input), price: try .init(transferring: &input))
    }
}

/// A value of eight bytes in memory that holds a reference, and states, wrongly, that it is stored
/// as its transfer bytes. The collections refuse to copy its memory, which would copy the reference
/// without retaining it, and write and read it one element at a time.
struct Handle: Equatable, Transferable {
    final class Box: Sendable {
        let value: UInt64

        init(value: UInt64) {
            self.value = value
        }
    }

    let box: Box

    static func == (a: Self, b: Self) -> Bool { a.box.value == b.box.value }

    static var transferLayout: TransferLayout? { .bitwise(size: 8) }
    var transferSize: Int { 8 }

    func transfer(into output: inout TransferWriter) {
        self.box.value.transfer(into: &output)
    }
    init(_ value: UInt64) {
        self.box = .init(value: value)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(try UInt64.init(transferring: &input))
    }
}

/// A wrapper that states it is stored as its transfer bytes but writes and reads itself, one at a
/// time, big-endian: a probe, which shows which path an array took, since the copy of its storage
/// is little-endian on a little-endian host.
struct Probe: Equatable, Transferable {
    let value: UInt64

    static var transferLayout: TransferLayout? { UInt64.transferLayout }
    var transferSize: Int { 8 }

    func transfer(into output: inout TransferWriter) {
        self.value.bigEndian.transfer(into: &output)
    }
    init(_ value: UInt64) {
        self.value = value
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(UInt64.init(bigEndian: try .init(transferring: &input)))
    }
}
