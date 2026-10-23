import DistributedABI

/// A composite of two `UInt32`, which states that it is stored as its transfer bytes as the
/// derive macro would: from its fields’ own statements and its layout, checked in code.
struct Pair: Equatable, Transferable {
    let low: UInt32
    let high: UInt32

    static var fixedTransferSize: Int? {
        guard
        let low: Int = UInt32.fixedTransferSize,
        let high: Int = UInt32.fixedTransferSize else {
            return nil
        }
        return low + high
    }
    static var isBitwiseTransferable: Bool {
        UInt32.isBitwiseTransferable
            && UInt32.isBitwiseTransferable
            && MemoryLayout<Self>.offset(of: \Self.low) == 0
            && MemoryLayout<Self>.offset(of: \Self.high) == MemoryLayout<UInt32>.size
            && MemoryLayout<Self>.size == MemoryLayout<UInt32>.size + MemoryLayout<UInt32>.size
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

/// A composite that states it is stored as its transfer bytes although it is not: nine bytes on
/// the wire, a stride of sixteen in memory. An array of them must travel one element at a time.
struct TrailingPadding: Equatable, Transferable {
    let price: Int64
    let side: UInt8

    static var fixedTransferSize: Int? { 9 }
    static var isBitwiseTransferable: Bool { true }
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

    static var fixedTransferSize: Int? { 9 }
    static var isBitwiseTransferable: Bool {
        UInt8.isBitwiseTransferable
            && Int64.isBitwiseTransferable
            && MemoryLayout<Self>.offset(of: \Self.side) == 0
            && MemoryLayout<Self>.offset(of: \Self.price) == MemoryLayout<UInt8>.size
            && MemoryLayout<Self>.size == MemoryLayout<UInt8>.size + MemoryLayout<Int64>.size
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

    static var fixedTransferSize: Int? { 8 }
    static var isBitwiseTransferable: Bool { true }
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

    static var fixedTransferSize: Int? { 8 }
    static var isBitwiseTransferable: Bool { UInt64.isBitwiseTransferable }
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
