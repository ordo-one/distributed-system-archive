import DistributedABI
import Testing

//  The reader borrows the bytes it reads and cannot outlive them, and neither can the spans it
//  hands out. None of these compiles, and no test can express that, so the diagnostics are
//  recorded here (Swift 6.4, in this test target, which builds without the `Lifetimes`
//  feature):
//
//      func escape(_ bytes: [UInt8]) -> TransferReader {
//          .init(bytes.span.bytes)
//      }
//      // error: a function cannot return a ~Escapable result
//
//      func escape(_ bytes: [UInt8]) -> () -> Int {
//          var input: TransferReader = .init(bytes.span.bytes)
//          let span: RawSpan = input.readRemainingBytes()
//          return { span.byteCount }
//      }
//      // error: lifetime-dependent variable 'span' escapes its scope
//
//      func escape() -> Int {
//          var input: TransferReader
//          do {
//              let bytes: [UInt8] = [1, 2, 3]
//              input = .init(bytes.span.bytes)
//          }
//          return input.remaining
//      }
//      // error: lifetime-dependent variable 'input' escapes its scope

@Suite enum Reader {
    @Test(arguments: [0, 1, 4, 9]) static func Bytes(_ count: Int) throws {
        let bytes: [UInt8] = .init(0 ..< 9)
        var input: TransferReader = .init(bytes.span.bytes)
        let head: RawSpan = try input.readBytes(count: count)
        #expect(head.byteCount == count)
        #expect(input.remaining == 9 - count)
        let tail: RawSpan = input.readRemainingBytes()
        #expect(tail.byteCount == 9 - count)
        #expect(input.remaining == 0)
        try input.readEnd()
    }

    /// The variable-length API: a ULEB128 length, then the bytes, both ways.
    @Test(arguments: [0, 1, 127, 128, 255, 256, 16_384]) static func Prefixed(_ length: Int) throws {
        let payload: [UInt8] = (0 ..< length).map { UInt8.init(truncatingIfNeeded: $0) }
        let bytes: [UInt8] = .init(capacity: ULEB128.size(length) + length) {
            $0.append(prefixed: payload.span.bytes)
        }
        #expect(bytes.count == ULEB128.size(length) + length)

        var input: TransferReader = .init(bytes.span.bytes)
        let span: RawSpan = try input.readPrefixedBytes()
        try input.readEnd()
        #expect(span.withUnsafeBytes { [UInt8].init($0) } == payload)
    }

    /// One byte, a little-endian integer and a value, each read as the writer appended it, and
    /// the end of the input read last; a byte past the end is refused as an integer is.
    @Test static func Reads() throws {
        let bytes: [UInt8] = .init(capacity: 16) {
            $0.append(7)
            $0.append(littleEndian: 0x0102_0304 as UInt32)
            $0.append(element: -2 as Int16)
            $0.append(uleb128: 1)
            $0.append(0xaa)
        }
        #expect(bytes == [7, 4, 3, 2, 1, 0xfe, 0xff, 1, 0xaa])

        var input: TransferReader = .init(bytes.span.bytes)
        #expect(try input.readByte() == 7)
        #expect(try input.read(littleEndian: UInt32.self) == 0x0102_0304)
        let value: Int16 = try input.read()
        #expect(value == -2)
        #expect(try input.readCount() == 1)
        #expect(try input.readByte() == 0xaa)
        try input.readEnd()
        let error: TransferError = try #require(throws: TransferError.self) { try input.readByte() }
        #expect(HostileInput.Expectation.init(error.kind) == .truncated(needed: 1, remaining: 0))
    }

    /// A ULEB128 number read back as the writer appended it, with a byte behind it that the
    /// read must leave: as a `UInt`, and as an `Int` when it is one.
    @Test(arguments: [0, 127, 128, 16_383, 16_384, UInt.init(Int.max), .max] as [UInt])
    static func ULEB128RoundTrips(_ value: UInt) throws {
        let unsigned: [UInt8] = .init(capacity: 11) {
            $0.append(uleb128: value)
            $0.append(0xaa)
        }
        var input: TransferReader = .init(unsigned.span.bytes)
        #expect(try input.read(uleb128: UInt.self) == value)
        #expect(input.remaining == 1)

        guard
        let count: Int = .init(exactly: value) else {
            return
        }
        let signed: [UInt8] = .init(capacity: 11) {
            $0.append(uleb128: count)
            $0.append(0xaa)
        }
        #expect(signed == unsigned)
        input = .init(signed.span.bytes)
        #expect(try input.read(uleb128: Int.self) == count)
        #expect(input.remaining == 1)
    }

    /// A number above `Int.max` reads as a `UInt` and is refused as an `Int`, as a count above
    /// it is, with the reader past its bytes.
    @Test(arguments: [UInt.init(Int.max) + 1, .max]) static func ULEB128AboveIntMax(_ value: UInt) throws {
        let bytes: [UInt8] = .init(capacity: 10) { $0.append(uleb128: value) }
        var input: TransferReader = .init(bytes.span.bytes)
        #expect(try input.read(uleb128: UInt.self) == value)

        input = .init(bytes.span.bytes)
        let error: TransferError = try #require(throws: TransferError.self) {
            try input.read(uleb128: Int.self)
        }
        #expect(HostileInput.Expectation.init(error.kind) == .malformedULEB128(remaining: 0))
        #expect(input.remaining == 0)
    }

    /// A ULEB128 number cut short or not in canonical form, refused by both forms with the
    /// error `readCount()` reports for the same bytes, and the reader at `remaining`.
    @Test(
        arguments: [
            ([], .truncated(needed: 1, remaining: 0), 0),
            ([0x80], .truncated(needed: 1, remaining: 0), 0),
            ([0xff, 0xff], .truncated(needed: 1, remaining: 0), 0),
            ([0x80, 0x00], .malformedULEB128(remaining: 0), 0),
            ([0x81, 0x00, 0x09], .malformedULEB128(remaining: 1), 1),
            (.init(repeating: 0x80, count: 10) + [0x01], .malformedULEB128(remaining: 0), 0),
        ] as [([UInt8], HostileInput.Expectation, Int)]
    ) static func ULEB128Refusals(
        _ bytes: [UInt8],
        _ expected: HostileInput.Expectation,
        _ remaining: Int
    ) throws {
        var input: TransferReader = .init(bytes.span.bytes)
        let unsigned: TransferError = try #require(throws: TransferError.self) {
            try input.read(uleb128: UInt.self)
        }
        #expect(HostileInput.Expectation.init(unsigned.kind) == expected)
        #expect(input.remaining == remaining)

        input = .init(bytes.span.bytes)
        let signed: TransferError = try #require(throws: TransferError.self) {
            try input.read(uleb128: Int.self)
        }
        #expect(HostileInput.Expectation.init(signed.kind) == expected)
        #expect(input.remaining == remaining)

        input = .init(bytes.span.bytes)
        let count: TransferError = try #require(throws: TransferError.self) { try input.readCount() }
        #expect(HostileInput.Expectation.init(count.kind) == expected)
    }

    /// Several values read in order from one buffer, as a composite reads its fields.
    @Test static func Fields() throws {
        let bytes: [UInt8] = .init(capacity: 64) {
            (0x0102 as UInt16).transfer(into: &$0)
            "abc".transfer(into: &$0)
            ([1, 2] as [Int8]).transfer(into: &$0)
            (nil as String?).transfer(into: &$0)
        }
        #expect(bytes == [0x02, 0x01, 3, 0x61, 0x62, 0x63, 2, 1, 2, 0])

        var input: TransferReader = .init(bytes.span.bytes)
        #expect(try UInt16.init(transferring: &input) == 0x0102)
        #expect(try String.init(transferring: &input) == "abc")
        #expect(try [Int8].init(transferring: &input) == [1, 2])
        #expect(try String?.init(transferring: &input) == nil)
        try input.readEnd()
    }

    @Test(
        arguments: [
            (.truncated(needed: 8, remaining: 3), "expected 8 byte(s), but 3 remain"),
            (.trailingBytes(remaining: 2), "expected end of input, but 2 byte(s) remain"),
            (.excessiveCount(9, remaining: 1), "count or length 9 exceeds the 1 byte(s) remaining"),
            (.malformedULEB128(remaining: 0), "malformed ULEB128 number, with 0 byte(s) remaining"),
            (.invalidDiscriminant(2), "invalid discriminant (2)"),
            (.duplicate(at: 3), "duplicate element at position [3]"),
            (.payload(Row.Refusal.empty), "empty"),
        ] as [(TransferError.Kind, String)]
    ) static func Descriptions(_ kind: TransferError.Kind, _ expected: String) {
        #expect("\(TransferError.init(kind))" == expected)
    }
}
