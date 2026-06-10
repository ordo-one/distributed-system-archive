import Testing
@testable import DistributedABI

/// Wire-parity tests for the zero-copy ``SpanDecoder``.
///
/// For a representative value of every supported type, we encode once with
/// ``BufferEncoder`` and then decode the SAME bytes two ways:
///
///   * the `ArraySlice`-backed ``BufferDecoder`` (the production path today), and
///   * the borrowed-`RawSpan` ``SpanDecoder`` (the new zero-copy path).
///
/// We assert the `SpanDecoder` result equals the `BufferDecoder` result (and, for
/// good measure, equals the original value), so the two decoders are proven to
/// agree byte-for-byte on the wire format. We also assert both decoders fully
/// consume the buffer (`finish()` does not throw), catching off-by-one cursor bugs.
@Suite struct SpanDecoderParity {
    /// Encodes `original` and asserts `SpanDecoder` and `BufferDecoder` decode the
    /// resulting bytes to equal values, and that both consume the whole buffer.
    static func parity<T>(
        _ original: T
    ) throws where T: BufferEncodable & BufferDecodable & SpanDecodable & Equatable {
        var encoder: BufferEncoder = .init(preallocated: [])
        try original.encode(to: &encoder)
        let bytes: [UInt8] = .init(encoder.output)

        //  Reference path: ArraySlice-backed decoder.
        var bufferDecoder: BufferDecoder = .init(bytes[...])
        let viaBuffer: T = try .decode(from: &bufferDecoder)
        try bufferDecoder.finish()

        //  Zero-copy path: borrowed RawSpan decoder over the SAME bytes.
        let viaSpan: T = try bytes.withUnsafeBytes {
            (raw: UnsafeRawBufferPointer) throws -> T in
            var spanDecoder: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
            let value: T = try .decode(from: &spanDecoder)
            try spanDecoder.finish()
            return value
        }

        #expect(viaSpan == viaBuffer, "SpanDecoder disagreed with BufferDecoder")
        #expect(viaSpan == original, "SpanDecoder did not round-trip the original value")
    }

    // MARK: Scalars

    @Test static func bools() throws {
        try Self.parity(true)
        try Self.parity(false)
    }

    @Test static func signedIntegers() throws {
        try Self.parity(Int8.min);  try Self.parity(Int8(-7));  try Self.parity(Int8.max)
        try Self.parity(Int16.min); try Self.parity(Int16(-300)); try Self.parity(Int16.max)
        try Self.parity(Int32.min); try Self.parity(Int32(-70000)); try Self.parity(Int32.max)
        try Self.parity(Int64.min); try Self.parity(Int64(-5_000_000_000)); try Self.parity(Int64.max)
        try Self.parity(Int.min);   try Self.parity(Int(-42));   try Self.parity(Int.max)
    }

    @Test static func unsignedIntegers() throws {
        try Self.parity(UInt8.min);  try Self.parity(UInt8(200));  try Self.parity(UInt8.max)
        try Self.parity(UInt16.min); try Self.parity(UInt16(40000)); try Self.parity(UInt16.max)
        try Self.parity(UInt32.min); try Self.parity(UInt32(3_000_000_000)); try Self.parity(UInt32.max)
        try Self.parity(UInt64.min); try Self.parity(UInt64(10_000_000_000)); try Self.parity(UInt64.max)
        try Self.parity(UInt.min);   try Self.parity(UInt(99));    try Self.parity(UInt.max)
    }

    @Test static func floatingPoint() throws {
        try Self.parity(Double(0))
        try Self.parity(Double(19.89))
        try Self.parity(Double(-13))
        try Self.parity(Double.infinity)
        try Self.parity(-Double.infinity)
        try Self.parity(Float(0))
        try Self.parity(Float(3.5))
        try Self.parity(Float(-2.25))
        try Self.parity(Float.infinity)
    }

    /// `==` cannot assert NaN and does not distinguish `-0.0` from `0.0`, so the
    /// generic `parity(_:)` helper would silently pass those values. Compare bit
    /// patterns instead, holding the wire encoding of every special float value to
    /// SpanDecoder == BufferDecoder == original.
    @Test static func floatingPointBitPatterns() throws {
        func parityBits<F>(_ value: F, _ bits: (F) -> UInt64) throws
            where F: BufferEncodable & BufferDecodable & SpanDecodable {
            var encoder: BufferEncoder = .init(preallocated: [])
            try value.encode(to: &encoder)
            let bytes: [UInt8] = .init(encoder.output)

            var bufferDecoder: BufferDecoder = .init(bytes[...])
            let viaBuffer: F = try .decode(from: &bufferDecoder)

            let viaSpan: F = try bytes.withUnsafeBytes {
                (raw: UnsafeRawBufferPointer) throws -> F in
                var spanDecoder: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
                return try .decode(from: &spanDecoder)
            }
            #expect(bits(viaSpan) == bits(viaBuffer), "SpanDecoder disagreed with BufferDecoder")
            #expect(bits(viaSpan) == bits(value), "SpanDecoder did not round-trip the original")
        }
        try parityBits(-Double(0)) { $0.bitPattern }
        try parityBits(Double.nan) { $0.bitPattern }
        try parityBits(Double(bitPattern: 0x7FF0_0000_0000_0001)) { $0.bitPattern } // signaling NaN
        try parityBits(Double(bitPattern: .max)) { $0.bitPattern }                  // all-ones
        try parityBits(-Float(0)) { UInt64($0.bitPattern) }
        try parityBits(Float.nan) { UInt64($0.bitPattern) }
        try parityBits(Float(bitPattern: 0x7F80_0001)) { UInt64($0.bitPattern) }    // signaling NaN
        try parityBits(Float(bitPattern: .max)) { UInt64($0.bitPattern) }
    }

    // MARK: RawRepresentable (generic default)

    enum Color: UInt8, BufferEncodable, BufferDecodable, SpanDecodable, Equatable {
        case red = 1
        case green = 7
        case blue = 200
    }

    @Test static func rawRepresentable() throws {
        try Self.parity(Color.red)
        try Self.parity(Color.green)
        try Self.parity(Color.blue)
        try Self.parity([Color.red, .blue, .green])
        try Self.parity(Color.green as Color?)
    }

    // MARK: Strings

    @Test static func strings() throws {
        try Self.parity("")
        try Self.parity("Hi Barbie!")
        try Self.parity("¡Hola Barbie!")
        //  embedded NUL forces the .long format
        try Self.parity("¡Hola\u{0}Barbie!")
        try Self.parity(String(repeating: "xyz\u{0}", count: 100))
        //  the 256-byte compact/long boundary, both sides
        try Self.parity(String(repeating: "a", count: 256))
        try Self.parity(String(repeating: "a", count: 257))
    }

    @Test static func substrings() throws {
        try Self.parity("Hi Barbie!"[...])
        try Self.parity(""[...])
        try Self.parity(String(repeating: "a", count: 257)[...])
    }

    // MARK: Optionals (including deeply nested)

    @Test static func optionals() throws {
        try Self.parity(nil as Int?)
        try Self.parity(42 as Int?)
        try Self.parity(nil as String?)
        try Self.parity("hi" as String?)
        //  deep optionals
        try Self.parity(.some(.some(7)) as Int??)
        try Self.parity(.some(nil) as Int??)
        try Self.parity(nil as Int??)
        try Self.parity(.some(.some(.some("deep"))) as String???)
        try Self.parity(.some(.some(nil)) as String???)
    }

    // MARK: Arrays (including nested and the >255 boundary)

    @Test static func arrays() throws {
        try Self.parity([] as [Int])
        try Self.parity([1, 2, 3] as [Int])
        try Self.parity(["", "a", "abc"] as [String])
        try Self.parity([[String]]())
        try Self.parity([["", "a"], [], ["abc"]] as [[String]])
        try Self.parity([nil, 1, nil, 2] as [Int?])
        //  300 elements crosses the single-byte CollectionHeader boundary (>= 255)
        try Self.parity(Array(0 ..< 300).map { UInt16($0) })
        //  exactly the 255-element boundary where the long header kicks in
        try Self.parity(Array(repeating: UInt8(1), count: 255))
        try Self.parity(Array(repeating: UInt8(1), count: 254))
    }

    @Test static func arraySlices() throws {
        try Self.parity(ArraySlice<Int>())
        try Self.parity([10, 20, 30][...])
        try Self.parity(Array(0 ..< 300).map { UInt16($0) }[...])
    }

    // MARK: Sets (including nested)

    @Test static func sets() throws {
        try Self.parity(Set<Int>())
        try Self.parity(Set([1, 2, 3]))
        try Self.parity(Set(["", "a", "abc"]))
        try Self.parity(Set<Set<Int>>())
        try Self.parity(Set([Set([1, 2]), Set<Int>(), Set([3])]))
        //  >255 distinct elements crosses the CollectionHeader boundary
        try Self.parity(Set(0 ..< 300))
    }

    // MARK: Dictionaries (including nested)

    @Test static func dictionaries() throws {
        try Self.parity([String: Int]())
        try Self.parity(["": 0])
        try Self.parity(["a": 1, "b": 2, "abc": 3] as [String: Int])
        try Self.parity([[String: Int]: [String: Int]]())
        try Self.parity([["a": 1]: ["b": 2], ["x": 3]: ["y": 4]] as [[String: Int]: [String: Int]])
        //  >255 entries crosses the CollectionHeader boundary
        var big: [Int: Int] = [:]
        for i in 0 ..< 300 { big[i] = i &* 2 }
        try Self.parity(big)
    }

    // MARK: Empty collections of every flavor

    @Test static func emptyCollections() throws {
        try Self.parity([Int]())
        try Self.parity(ArraySlice<Int>())
        try Self.parity(Set<Int>())
        try Self.parity([Int: Int]())
        try Self.parity("")
        try Self.parity(""[...])
        try Self.parity([[Int]]())
    }
}
