import DistributedABI
import Testing

//  Proves the borrowed-span (zero-copy) paths produce byte- and value-identical
//  results to the owned `[UInt8]` paths, plus exercises the collection-header
//  boundary, float bit patterns, and collision detection.
@Suite struct ZeroCopyParity {
    /// Owned encode (`encoded()`) and zero-copy encode (into a reserved
    /// `UnsafeMutableRawBufferPointer`) must emit identical bytes.
    static func encodeParity<T>(_ value: T) where T: BufferEncodable {
        let owned: [UInt8] = value.encoded()
        let region: UnsafeMutableRawBufferPointer = .allocate(
            byteCount: Swift.max(value.encodedSize, 1),
            alignment: 16
        )
        defer { region.deallocate() }
        let written: Int = value.encode(into: region)
        let zeroCopy: [UInt8] = .init(region[0 ..< written])
        #expect(owned == zeroCopy)
        #expect(written <= value.encodedSize)   // encodedSize is a valid upper bound
    }

    /// Owned decode (borrowing `[UInt8]`) and zero-copy decode (over a `RawSpan`
    /// built from foreign memory) must yield equal values.
    static func decodeParity<T>(_ value: T) throws where T: BufferEncodable & BufferDecodable & Equatable {
        let wire: [UInt8] = value.encoded()
        let owned: T = try .decode(wire)
        let zeroCopy: T = try wire.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> T in
            var index: Int = 0
            let span: RawSpan = .init(_unsafeBytes: raw)
            let decoded: T = try T.decode(from: span, at: &index)
            #expect(index == raw.count)   // exact consumption, no trailing bytes
            return decoded
        }
        #expect(owned == value)
        #expect(zeroCopy == value)
    }

    static func parity<T>(_ value: T) throws where T: BufferEncodable & BufferDecodable & Equatable {
        Self.encodeParity(value)
        try Self.decodeParity(value)
    }

    @Test static func Scalars() throws {
        try Self.parity(Int.min)
        try Self.parity(UInt64.max)
        try Self.parity(true)
        try Self.parity(false)
        try Self.parity("Hello, zero-copy")
        try Self.parity("¡Hola\u{0}Barbie!")
        try Self.parity([1, 2, 3] as [UInt8])
        try Self.parity(["a": 1, "bb": 2] as [String: Int])
        try Self.parity(Optional<Int>.some(7))
        try Self.parity(Optional<Int>.none)
    }

    /// Float / Double bit patterns must survive the round trip exactly.
    @Test static func FloatBitPatterns() throws {
        Self.encodeParity(Double.nan)
        Self.encodeParity(-0.0 as Double)
        Self.encodeParity(Float.signalingNaN)
        #expect(try Double.decode((-0.0 as Double).encoded()).sign == .minus)
        #expect(try Double.decode(Double.nan.encoded()).isNaN)
        #expect(try Float.decode(Float.signalingNaN.encoded()).isSignalingNaN)
    }

    /// The collection-header switches from a 1-byte to a 9-byte encoding at 255.
    @Test(arguments: [0, 1, 254, 255, 256, 300]) static func CollectionHeaderBoundary(_ n: Int) throws {
        let value: [UInt8] = .init(repeating: 0x2A, count: n)
        try Self.parity(value)
        let wire: [UInt8] = value.encoded()
        // header is 1 byte for count < 255, else 1 (0xFF marker) + 8 (Int) = 9 bytes
        let headerSize: Int = n < 255 ? 1 : 9
        #expect(wire.count == headerSize + n)
    }

    @Test static func SetCollisionThrows() {
        // two equal elements ("a") encoded as a 2-element collection
        let wire: [UInt8] = [2, 0, 0x61, 0, 0, 0x61, 0]
        #expect(throws: BufferDecodingError.self) {
            let _: Set<String> = try .decode(wire)
        }
    }

    @Test static func DictionaryCollisionThrows() {
        // two pairs with the same key "a"
        let wire: [UInt8] = [2, 0, 0x61, 0, 0, 0x62, 0, 0, 0x61, 0, 0, 0x63, 0]
        #expect(throws: BufferDecodingError.self) {
            let _: [String: String] = try .decode(wire)
        }
    }
}
