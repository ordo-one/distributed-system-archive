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
//          let span: RawSpan = input.takeRemaining()
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
    @Test(arguments: [0, 1, 4, 9]) static func Take(_ count: Int) throws {
        let bytes: [UInt8] = .init(0 ..< 9)
        var input: TransferReader = .init(bytes.span.bytes)
        let head: RawSpan = try input.take(count)
        #expect(head.byteCount == count)
        #expect(input.remaining == 9 - count)
        let tail: RawSpan = input.takeRemaining()
        #expect(tail.byteCount == 9 - count)
        #expect(input.remaining == 0)
        try input.finish()
    }

    /// The variable-length API: a ULEB128 length, then the bytes, both ways.
    @Test(arguments: [0, 1, 127, 128, 255, 256, 16_384]) static func Prefixed(_ length: Int) throws {
        let payload: [UInt8] = (0 ..< length).map { UInt8.init(truncatingIfNeeded: $0) }
        let bytes: [UInt8] = .init(capacity: ULEB128.size(UInt.init(length)) + length) {
            $0.append(prefixed: payload.span.bytes)
        }
        #expect(bytes.count == ULEB128.size(UInt.init(length)) + length)

        var input: TransferReader = .init(bytes.span.bytes)
        let span: RawSpan = try input.takePrefixed()
        try input.finish()
        #expect(span.withUnsafeBytes { [UInt8].init($0) } == payload)
    }

    /// Several values read in order from one buffer, as a composite reads its fields.
    @Test static func Fields() throws {
        let bytes: [UInt8] = .init(capacity: 64) {
            $0.append(framed: 0x0102 as UInt16)
            $0.append(framed: "abc")
            $0.append(framed: [1, 2] as [Int8])
            $0.append(framed: nil as String?)
        }
        #expect(bytes == [0x02, 0x01, 3, 0x61, 0x62, 0x63, 3, 2, 1, 2, 1, 0])

        var input: TransferReader = .init(bytes.span.bytes)
        #expect(try input.take(framed: UInt16.self) == 0x0102)
        #expect(try input.take(framed: String.self) == "abc")
        #expect(try input.take(framed: [Int8].self) == [1, 2])
        #expect(try input.take(framed: String?.self) == nil)
        try input.finish()
    }

    @Test(
        arguments: [
            (.expected(8, encountered: 3), "expected 8 byte(s), but 3 remain"),
            (.expected(0, encountered: 2), "expected end of input, but 2 byte(s) remain"),
            (.count(9, remaining: 1), "count or length 9 exceeds the 1 byte(s) remaining"),
            (.count(-1, remaining: 0), "malformed ULEB128 number, with 0 byte(s) remaining"),
            (.discriminant(2), "invalid discriminant (2)"),
            (.duplicate(3), "duplicate element at position [3]"),
            (.payload(Row.Refusal.empty), "empty"),
        ] as [(TransferError.Kind, String)]
    ) static func Descriptions(_ kind: TransferError.Kind, _ expected: String) {
        #expect("\(TransferError.init(kind))" == expected)
    }
}
