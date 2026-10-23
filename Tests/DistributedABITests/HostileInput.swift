import DistributedABI
import Testing

@Suite enum HostileInput {
    /// Malformed and hostile bytes are refused with an error, never a trap, and a count or
    /// length the bytes present could not hold is refused before anything is reserved.
    @Test(
        arguments: [
            // too few bytes for a fixed-size value
            Hostile.init("short integer", [1, 2, 3], as: Int.self, .expected(8, encountered: 3)),
            Hostile.init("empty integer", [], as: UInt16.self, .expected(2, encountered: 0)),
            Hostile.init("bytes left over", [0, 0, 0, 0, 1], as: Int32.self, .expected(0, encountered: 1)),
            // discriminants out of range
            Hostile.init("bool", [2], as: Bool.self, .discriminant(2)),
            Hostile.init("optional", [0xff], as: Int?.self, .discriminant(255)),
            Hostile.init("result", [7, 1], as: Result<UInt8, Failure>.self, .discriminant(7)),
            Hostile.init("signed raw value", [0x80], as: Side.self, .discriminant(0x80)),
            Hostile.init("wide raw value", [0, 0], as: Venue.self, .discriminant(0)),
            Hostile.init("empty inline array", [1], as: InlineArray<0, Int64>.self, .discriminant(1)),
            Hostile.init("empty inline array in an array", [2, 0, 0xff], as: [InlineArray<0, UInt8>].self, .discriminant(255)),
            Hostile.init(
                "128-bit raw value past 64 bits",
                .init(repeating: 0, count: 8) + [1] + .init(repeating: 0, count: 7),
                as: Wide.self,
                .discriminant(1 << 64)
            ),
            Hostile.init(
                "negative 128-bit raw value",
                .init(repeating: 0xff, count: 16),
                as: WideSigned.self,
                .discriminant(.max)
            ),
            // counts and lengths past the end
            Hostile.init("count past end", [5, 1, 2], as: [UInt8].self, .count(5, remaining: 2)),
            Hostile.init("packed count past end", [2] + .init(repeating: 0, count: 9), as: [Int].self, .count(2, remaining: 9)),
            Hostile.init("length past end", [1, 5, 0x61], as: [String].self, .count(5, remaining: 1)),
            Hostile.init("inner count past end", [1, 3, 9, 9], as: [[UInt8]].self, .count(3, remaining: 2)),
            Hostile.init("count of Int.max", Self.intMax, as: [UInt8].self, .count(.max, remaining: 0)),
            Hostile.init("count of 2^30", [0x80, 0x80, 0x80, 0x80, 0x04], as: [UInt64].self, .count(1 << 30, remaining: 0)),
            Hostile.init("dictionary count of Int.max", Self.intMax, as: [UInt8: UInt8].self, .count(.max, remaining: 0)),
            Hostile.init("dictionary count past end", [2, 1, 1], as: [UInt8: UInt8].self, .count(2, remaining: 2)),
            Hostile.init("set count of Int.max", Self.intMax, as: Set<UInt8>.self, .count(.max, remaining: 0)),
            // counts within the bytes present, but not at the width of a fixed-size element
            Hostile.init("wide set count past end", [2] + .init(repeating: 0, count: 9), as: Set<UInt64>.self, .count(2, remaining: 9)),
            Hostile.init("contiguous count past end", [2, 1, 0, 2], as: ContiguousArray<Int16>.self, .count(2, remaining: 3)),
            Hostile.init("own collection count past end", [2, 1, 0, 2], as: Batch<Int16>.self, .count(2, remaining: 3)),
            Hostile.init(
                "inline array count past end",
                [2] + .init(repeating: 0, count: 9),
                as: [InlineArray<4, Int16>].self,
                .count(2, remaining: 9)
            ),
            Hostile.init("composite count past end", [2] + .init(repeating: 0, count: 9), as: [Ladder].self, .count(2, remaining: 9)),
            Hostile.init(
                "wide dictionary count past end",
                [2] + .init(repeating: 0, count: 17),
                as: [UInt64: UInt64].self,
                .count(2, remaining: 17)
            ),
            Hostile.init(
                "wide key count past end",
                [2] + .init(repeating: 0, count: 10),
                as: [UInt64: String].self,
                .count(2, remaining: 10)
            ),
            Hostile.init(
                "own keyed count past end",
                [2] + .init(repeating: 0, count: 17),
                as: Ledger<UInt64, UInt64>.self,
                .count(2, remaining: 17)
            ),
            // an entry whose least size cannot be represented
            Hostile.init("entry size past Int.max", [1, 0, 0], as: [Oversized: UInt8].self, .count(1, remaining: 2)),
            // an inline array whose fixed size cannot be represented, which states none
            Hostile.init("inline size past Int.max", [1, 1, 2], as: [InlineArray<2, Oversized>].self, .expected(.max, encountered: 1)),
            // malformed ULEB128
            Hostile.init(
                "count over Int.max",
                [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01],
                as: [UInt8].self,
                .malformed(remaining: 0)
            ),
            Hostile.init(
                "count over 64 bits",
                [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f],
                as: [UInt8].self,
                .malformed(remaining: 0)
            ),
            Hostile.init("eleven-byte count", .init(repeating: 0x80, count: 10) + [0x01], as: [UInt8].self, .malformed(remaining: 0)),
            Hostile.init("overlong zero", [0x80, 0x00], as: [UInt8].self, .malformed(remaining: 0)),
            Hostile.init("overlong one", [0x81, 0x00, 0x09], as: [UInt8].self, .malformed(remaining: 1)),
            Hostile.init("truncated count", [0x80], as: [UInt8].self, .expected(1, encountered: 0)),
            Hostile.init("missing count", [], as: [String: Int].self, .expected(1, encountered: 0)),
            Hostile.init("truncated length", [1, 0x80], as: [String].self, .expected(1, encountered: 0)),
            Hostile.init("contiguous array cut short", [2, 1, 0x61], as: ContiguousArray<String>.self, .expected(1, encountered: 0)),
            Hostile.init("inline array cut short", [1, 0, 0, 0, 2, 0], as: InlineArray<2, UInt32>.self, .expected(4, encountered: 2)),
            Hostile.init("inline strings cut short", [2, 0x61, 0x62], as: InlineArray<2, String>.self, .expected(1, encountered: 0)),
            Hostile.init("empty inline array without its byte", [], as: InlineArray<0, String>.self, .expected(1, encountered: 0)),
            // the length of a contiguous value, whose two-byte form is read inline
            Hostile.init("overlong zero length", [0x80, 0x00], as: Row.self, .malformed(remaining: 0)),
            Hostile.init("two-byte length past end", [0x80, 0x01, 9], as: Row.self, .count(128, remaining: 1)),
            Hostile.init("truncated two-byte length", [0x80], as: Row.self, .expected(1, encountered: 0)),
            // bytes left over after the last element
            Hostile.init("bytes left over after elements", [1, 1, 7, 0xaa], as: [UInt8?].self, .expected(0, encountered: 1)),
            Hostile.init(
                "bytes left over after an empty inline array",
                [0, 0],
                as: InlineArray<0, UInt8>.self,
                .expected(0, encountered: 1)
            ),
            // an element of fixed size that reads fewer bytes than its type states
            Hostile.init("fixed-size element read short", [1, 5, 6], as: [Undersized].self, .expected(2, encountered: 1)),
            Hostile.init("fixed-size key read short", [1, 5, 6, 7], as: [Undersized: UInt8].self, .expected(2, encountered: 1)),
            Hostile.init("fixed-size inline element read short", [5, 6], as: InlineArray<1, Undersized>.self, .expected(2, encountered: 1)),
            // and one that reads more, wherever a collection reads it
            Hostile.init("fixed-size element read long", [1, 5, 6], as: [Overreader].self, .expected(1, encountered: 2)),
            Hostile.init("fixed-size key read long", [1, 5, 6, 7], as: [Overreader: UInt8].self, .expected(1, encountered: 2)),
            Hostile.init("fixed-size value read long", [1, 7, 5, 6], as: [UInt8: Overreader].self, .expected(1, encountered: 2)),
            Hostile.init("fixed-size inline element read long", [5, 6], as: InlineArray<1, Overreader>.self, .expected(1, encountered: 2)),
            Hostile.init("fixed-size element of one’s own read long", [1, 5, 6], as: Batch<Overreader>.self, .expected(1, encountered: 2)),
            Hostile.init(
                "fixed-size key of one’s own read long",
                [1, 5, 6, 7],
                as: Ledger<Overreader, UInt8>.self,
                .expected(1, encountered: 2)
            ),
            // duplicates
            Hostile.init("set duplicate", [3, 5, 6, 5], as: Set<UInt8>.self, .duplicate(2)),
            Hostile.init("dictionary duplicate", [2, 1, 1, 1, 2], as: [UInt8: UInt8].self, .duplicate(1)),
            // a conformer’s own refusal
            Hostile.init("invalid UTF-8", [2, 0xc3, 0x28], as: String.self, .payload),
            Hostile.init("refused row", [1, 0], as: [Row].self, .payload),
        ]
    ) static func Refused(_ hostile: Hostile) throws {
        let error: TransferError = try #require(throws: TransferError.self) {
            try hostile.decode(hostile.bytes)
        }
        #expect(Expectation.init(error.kind) == hostile.expected)
    }

    @Test(arguments: [-1, -.max, 4]) static func TakeCountOutOfRange(_ count: Int) throws {
        let bytes: [UInt8] = [1, 2, 3]
        var input: TransferReader = .init(bytes.span.bytes)
        let error: TransferError?
        do {
            _ = try input.take(count)
            error = nil
        } catch let refusal {
            error = refusal
        }
        #expect(error.map { Expectation.init($0.kind) } == .expected(count, encountered: 3))
        #expect(input.remaining == 3)
    }

    /// An empty dictionary reads even when the least size of an entry cannot be represented,
    /// since it has no entry to make room for.
    @Test static func EmptyDictionaryOfOversizedKeys() throws {
        let empty: [Oversized: UInt8] = [:]
        let bytes: [UInt8] = .init(transferring: empty)
        #expect(bytes == [0])
        #expect(try [Oversized: UInt8].decode(bytes) == empty)
    }

    /// A conformer’s error arrives unchanged, so the transport can tell a refusal from damage.
    @Test static func PayloadUnchanged() throws {
        let error: TransferError = try #require(throws: TransferError.self) {
            try Row.decode([0])
        }
        let refusal: Row.Refusal?
        if  case .payload(let error as Row.Refusal) = error.kind {
            refusal = error
        } else {
            refusal = nil
        }
        #expect(refusal == .empty)
    }
}
extension HostileInput {
    private static var intMax: [UInt8] { [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f] }
}
