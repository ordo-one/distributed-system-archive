import DistributedABI
import Testing

/// Arrays of elements stored as their transfer bytes travel as one copy of their storage, with
/// the bytes on the wire, and every refusal, exactly those of a read one element at a time.
@Suite enum Bitwise {
    /// The fixed-width integers, `Float` and `Double` state it on a little-endian host, and so
    /// do a wrapper and a composite that state it from their parts; nothing else does by
    /// default, an enumeration with an integer raw value included.
    @Test(
        arguments: [
            (Int8.self, true), (Int16.self, true), (Int32.self, true), (Int64.self, true),
            (Int128.self, true), (Int.self, true),
            (UInt8.self, true), (UInt16.self, true), (UInt32.self, true), (UInt64.self, true),
            (UInt128.self, true), (UInt.self, true),
            (Float.self, true), (Double.self, true),
            (Ticket.self, true), (Pair.self, true),
            (Bool.self, false), (String.self, false), (Side.self, false), (Venue.self, false),
            (Int?.self, false), (UnstatedTicket.self, false), (Identifier.self, false),
            ([UInt64].self, false), (InlineArray<2, UInt64>.self, false), (InteriorPadding.self, false),
        ] as [(any Transferable.Type, Bool)]
    ) static func Stated(_ type: any Transferable.Type, _ onLittleEndian: Bool) {
        #if _endian(little)
        #expect(type.isBitwiseTransferable == onLittleEndian)
        #else
        #expect(!type.isBitwiseTransferable)
        #endif
    }

    /// An array, a contiguous array and a slice of wrappers that state it write the same bytes
    /// as wrappers that do not, spelled out here, and read back equal; the slice starts past
    /// the start of its array, and the counts cross the one- and two-byte forms of the count.
    @Test(arguments: [0, 1, 2, 127, 128, 1_000]) static func Arrays(_ count: Int) throws {
        let raw: [UInt64] = (0 ..< count).map { 0x0102_0304_0506_0708 &* UInt64.init($0 + 1) }
        let golden: [UInt8] = Self.uleb128(count) + raw.flatMap(Self.littleEndian(_:))
        let tickets: [Ticket] = raw.map(Ticket.init(rawValue:))
        let unstated: [UnstatedTicket] = raw.map(UnstatedTicket.init(rawValue:))

        #expect([UInt8].init(transferring: tickets) == golden)
        #expect([UInt8].init(transferring: unstated) == golden)
        #expect(try [Ticket].decode(golden) == tickets)

        #expect([UInt8].init(transferring: ContiguousArray.init(tickets)) == golden)
        #expect(try ContiguousArray<Ticket>.decode(golden) == ContiguousArray.init(tickets))

        let wider: [Ticket] = [.init(rawValue: 9)] + tickets + [.init(rawValue: 9)]
        let slice: ArraySlice<Ticket> = wider[1 ..< 1 + count]
        #expect([UInt8].init(transferring: slice) == golden)
        #expect(try ArraySlice<Ticket>.decode(golden) == slice)
    }

    /// An inline array of wrappers that state it writes its elements with no count, the same
    /// bytes as one of wrappers that do not, and an empty one still writes one zero byte.
    @Test static func InlineArrays() throws {
        let golden: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0] + .init(repeating: 0xff, count: 8)
        let tickets: InlineArray<3, Ticket> = [.init(rawValue: 1), .init(rawValue: 0x0102), .init(rawValue: .max)]
        let unstated: InlineArray<3, UnstatedTicket> = [
            .init(rawValue: 1),
            .init(rawValue: 0x0102),
            .init(rawValue: .max),
        ]
        #expect([UInt8].init(transferring: tickets) == golden)
        #expect([UInt8].init(transferring: unstated) == golden)
        #expect([UInt8].init(transferring: try InlineArray<3, Ticket>.decode(golden)) == golden)
        #expect([UInt8].init(transferring: [] as InlineArray<0, Ticket>) == [0])
    }

    /// A composite that states it from its fields and its layout travels as their bytes in
    /// declaration order.
    @Test static func Composites() throws {
        let pairs: [Pair] = [.init(low: 0x0102_0304, high: 5), .init(low: .max, high: 0)]
        let golden: [UInt8] = [2, 4, 3, 2, 1, 5, 0, 0, 0, 0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0]
        #expect([UInt8].init(transferring: pairs) == golden)
        #expect(try [Pair].decode(golden) == pairs)
    }

    /// Elements that state it although their memory is not their transfer bytes, or holds a
    /// reference, travel one at a time: the collection checks the size, the stride and the
    /// absence of references itself, so it never copies a padding byte or a reference.
    @Test static func Misdeclared() throws {
        let trailing: [TrailingPadding] = [.init(price: 0x0102, side: 3), .init(price: -1, side: 4)]
        let trailingGolden: [UInt8] = [2, 2, 1, 0, 0, 0, 0, 0, 0, 3] + .init(repeating: 0xff, count: 8) + [4]
        #expect([UInt8].init(transferring: trailing) == trailingGolden)
        #expect(try [TrailingPadding].decode(trailingGolden) == trailing)
        #expect(try ContiguousArray<TrailingPadding>.decode(trailingGolden) == ContiguousArray.init(trailing))

        let interior: [InteriorPadding] = [.init(side: 3, price: 0x0102), .init(side: 4, price: -1)]
        let interiorGolden: [UInt8] = [2, 3, 2, 1, 0, 0, 0, 0, 0, 0, 4] + .init(repeating: 0xff, count: 8)
        #expect([UInt8].init(transferring: interior) == interiorGolden)
        #expect(try [InteriorPadding].decode(interiorGolden) == interior)

        let handles: [Handle] = [.init(0x0102), .init(7)]
        let handlesGolden: [UInt8] = [2, 2, 1, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0]
        #expect([UInt8].init(transferring: handles) == handlesGolden)
        #expect([UInt8].init(transferring: handles[...]) == handlesGolden)
        #expect(try [Handle].decode(handlesGolden) == handles)
        #expect(try ArraySlice<Handle>.decode(handlesGolden) == handles[...])
        let inline: InlineArray<2, Handle> = [.init(0x0102), .init(7)]
        #expect([UInt8].init(transferring: inline) == Array.init(handlesGolden.dropFirst()))
        #expect(
            [UInt8].init(transferring: try InlineArray<2, Handle>.decode(Array.init(handlesGolden.dropFirst()))) == Array.init(
                handlesGolden.dropFirst()
            )
        )
    }

    /// Each kind of array takes the copy of its storage, specialized or not: the probe writes
    /// itself big-endian one at a time, and its storage is little-endian.
    @Test static func TakesTheCopy() throws {
        #if _endian(little)
        let probes: [Probe] = [.init(0x0102), .init(0x0304)]
        let stored: [UInt8] = [2] + Self.littleEndian(0x0102) + Self.littleEndian(0x0304)
        #expect([UInt8].init(transferring: probes) == stored)
        #expect([UInt8].init(transferring: ContiguousArray.init(probes)) == stored)
        #expect([UInt8].init(transferring: probes[...]) == stored)
        #expect(try [Probe].decode(stored) == probes)
        #expect(try ContiguousArray<Probe>.decode(stored) == ContiguousArray.init(probes))
        #expect(try ArraySlice<Probe>.decode(stored) == probes[...])
        let inline: InlineArray<2, Probe> = [.init(0x0102), .init(0x0304)]
        #expect([UInt8].init(transferring: inline) == Array.init(stored.dropFirst()))
        let read: InlineArray<2, Probe> = try .decode(Array.init(stored.dropFirst()))
        #expect(read[0] == .init(0x0102) && read[1] == .init(0x0304))
        // one at a time, the probe writes itself big-endian
        #expect([UInt8].init(transferring: probes[0]) == Self.littleEndian(0x0102).reversed())
        #endif
    }

    /// Every NaN payload, signaling ones included, survives the copy.
    @Test static func FloatingPointBitPatterns() throws {
        let doubles: [Double] = [.nan, .signalingNaN, -0.0, .infinity, .init(bitPattern: 0x7ff0_0000_0000_0001)]
        let doubleBytes: [UInt8] = [5] + doubles.flatMap { Self.littleEndian($0.bitPattern) }
        #expect([UInt8].init(transferring: doubles) == doubleBytes)
        #expect(try [Double].decode(doubleBytes).map(\.bitPattern) == doubles.map(\.bitPattern))

        let floats: [Float] = [.nan, .signalingNaN, -0.0, .init(bitPattern: 0x7f80_0001)]
        let floatBytes: [UInt8] = [4] + floats.flatMap { (float: Float) in
            (0 ..< 4).map { UInt8.init(truncatingIfNeeded: float.bitPattern >> ($0 * 8)) }
        }
        #expect([UInt8].init(transferring: floats) == floatBytes)
        #expect(try [Float].decode(floatBytes).map(\.bitPattern) == floats.map(\.bitPattern))
    }

    /// Every prefix of a frame, and a hostile count, is refused by each kind of array with the
    /// error a read of one element at a time reports: the same kind, count and position.
    @Test(arguments: 0 ... 25) static func Truncated(_ length: Int) {
        let golden: [UInt8] = [3] + [1, 0x0102, .max].flatMap { Self.littleEndian($0 as UInt64) }
        let prefix: [UInt8] = .init(golden.prefix(length))
        #expect(Self.refusal(prefix, as: [Ticket].self) == Self.refusal(prefix, as: [UnstatedTicket].self))
        #expect(
            Self.refusal(prefix, as: ContiguousArray<Ticket>.self)
                == Self.refusal(prefix, as: ContiguousArray<UnstatedTicket>.self)
        )
        #expect(
            Self.refusal(prefix, as: ArraySlice<Ticket>.self)
                == Self.refusal(prefix, as: ArraySlice<UnstatedTicket>.self)
        )
        let inline: [UInt8] = .init(golden.dropFirst().prefix(length))
        #expect(
            Self.refusal(inline, as: InlineArray<3, Ticket>.self)
                == Self.refusal(inline, as: InlineArray<3, UnstatedTicket>.self)
        )
    }

    @Test(
        arguments: [
            [0x80, 0x80, 0x80, 0x80, 0x04],
            [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f],
            [2] + .init(repeating: 0, count: 15),
            [0x80, 0x00],
        ] as [[UInt8]]
    ) static func HostileCounts(_ bytes: [UInt8]) throws {
        let refusal: HostileInput.Expectation? = Self.refusal(bytes, as: [Ticket].self)
        #expect(refusal != nil)
        #expect(refusal == Self.refusal(bytes, as: [UnstatedTicket].self))
        #expect(refusal == Self.refusal(bytes, as: ContiguousArray<Ticket>.self))
        #expect(refusal == Self.refusal(bytes, as: ArraySlice<Ticket>.self))
    }

    /// An enumeration with an integer raw value, and `Bool`, are not stored as every byte
    /// they could read, so an array of them refuses a byte of no case where it stands.
    @Test static func EnumerationsRefuseEachElement() {
        #expect(Self.refusal([3, 0x01, 0xff, 0x05], as: [Side].self) == .discriminant(5))
        #expect(Self.refusal([3, 1, 0, 2], as: [Bool].self) == .discriminant(2))
    }

    /// `Bool` states two cases, and the enumeration of its case indices its three, and no
    /// other type states any by default.
    @Test static func CaseCounts() {
        #expect(Bool.bitwiseDiscriminantCount == 2)
        #expect(Mark.bitwiseDiscriminantCount == 3)
        #expect(UnstatedMark.bitwiseDiscriminantCount == nil)
        #expect(Side.bitwiseDiscriminantCount == nil)
        #expect(UInt8.bitwiseDiscriminantCount == nil)
    }

    /// Arrays of `Bool` and of an enumeration that states its case count write the bytes of a
    /// write one element at a time, spelled out here, and read them back equal.
    @Test(arguments: [0, 1, 3, 128]) static func CheckedArrays(_ count: Int) throws {
        let raw: [UInt8] = (0 ..< count).map { UInt8.init($0 % 3) }
        let golden: [UInt8] = Self.uleb128(count) + raw
        let marks: [Mark] = raw.map { Mark.init(rawValue: $0)! }
        #expect([UInt8].init(transferring: marks) == golden)
        #expect([UInt8].init(transferring: raw.map { UnstatedMark.init(rawValue: $0)! }) == golden)
        #expect(try [Mark].decode(golden) == marks)
        #expect(try ContiguousArray<Mark>.decode(golden) == ContiguousArray.init(marks))
        #expect(try ArraySlice<Mark>.decode(golden) == marks[...])

        let flags: [Bool] = raw.map { $0 == 1 }
        let flagBytes: [UInt8] = Self.uleb128(count) + flags.map { $0 ? 1 : 0 }
        #expect([UInt8].init(transferring: flags) == flagBytes)
        #expect(try [Bool].decode(flagBytes) == flags)
        #expect(try ContiguousArray<Bool>.decode(flagBytes) == ContiguousArray.init(flags))

        let inline: InlineArray<4, Mark> = [.at, .none, .near, .at]
        #expect([UInt8].init(transferring: inline) == [2, 0, 1, 2])
        #expect([UInt8].init(transferring: try InlineArray<4, Mark>.decode([2, 0, 1, 2])) == [2, 0, 1, 2])
    }

    /// A byte of no case, wherever it stands, and every prefix of a frame, are refused by each
    /// kind of array with the error a read of one element at a time reports.
    @Test(arguments: 0 ..< 5) static func CheckedRefusals(_ position: Int) {
        for bad: UInt8 in [3, 0x80, 0xff] {
            var bytes: [UInt8] = [5, 0, 1, 2, 1, 0]
            bytes[1 + position] = bad
            for length: Int in 0 ... bytes.count {
                let prefix: [UInt8] = .init(bytes.prefix(length))
                #expect(Self.refusal(prefix, as: [Mark].self) == Self.refusal(prefix, as: [UnstatedMark].self))
                #expect(
                    Self.refusal(prefix, as: ContiguousArray<Mark>.self)
                        == Self.refusal(prefix, as: ContiguousArray<UnstatedMark>.self)
                )
                #expect(
                    Self.refusal(prefix, as: ArraySlice<Mark>.self)
                        == Self.refusal(prefix, as: ArraySlice<UnstatedMark>.self)
                )
                let inline: [UInt8] = .init(bytes.dropFirst().prefix(length))
                #expect(
                    Self.refusal(inline, as: InlineArray<5, Mark>.self)
                        == Self.refusal(inline, as: InlineArray<5, UnstatedMark>.self)
                )
            }
            var flags: [UInt8] = [5, 0, 1, 1, 0, 1]
            flags[1 + position] = bad
            #expect(Self.refusal(flags, as: [Bool].self) == .discriminant(.init(bad)))
            #expect(Self.refusal(Array.init(flags.dropFirst()), as: InlineArray<5, Bool>.self) == .discriminant(.init(bad)))
        }
    }

    /// A type of more than one byte that states a case count travels one element at a time.
    @Test static func CaseCountOfAWideType() throws {
        let marks: [WideMark] = [.init(rawValue: 7), .init(rawValue: 0x0102)]
        let golden: [UInt8] = [2] + Self.littleEndian(7) + Self.littleEndian(0x0102)
        #expect([UInt8].init(transferring: marks) == golden)
        #expect(try [WideMark].decode(golden) == marks)
    }
}
extension Bitwise {
    /// The error decoding `bytes` reports, or nil when they decode.
    static func refusal<Value>(_ bytes: [UInt8], as _: Value.Type) -> HostileInput.Expectation?
        where Value: Transferable {
        do {
            _ = try Value.decode(bytes)
            return nil
        } catch {
            return .init(error.kind)
        }
    }

    /// The bytes of `value`, least significant first, spelled apart from the library.
    static func littleEndian(_ value: UInt64) -> [UInt8] {
        (0 ..< 8).map { UInt8.init(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    /// A count as ULEB128, spelled apart from the library.
    static func uleb128(_ value: Int) -> [UInt8] {
        var value: UInt = .init(value)
        var bytes: [UInt8] = []
        repeat {
            let low: UInt8 = .init(value & 0x7f)
            value >>= 7
            bytes.append(value == 0 ? low : low | 0x80)
        } while value != 0
        return bytes
    }
}
