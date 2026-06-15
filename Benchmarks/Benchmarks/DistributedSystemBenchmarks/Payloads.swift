import Benchmark
import DistributedABI

//  PRODUCTION-REPRESENTATIVE serialization payloads.
//
//  A payload census of the real data model (~/GitHub/package-data-model) found 1691 fields
//  that are 66% Optional, 11% String, 10% Array, and ZERO Dictionary/Set. The existing suite
//  only measures 10001-element arrays of isolated Int / String / Dictionary — none of which
//  resemble a real message. These replica types mirror the real shapes: structs of mixed
//  fixed-width + optional + short-string fields, plus a few identifier-array collections.
//
//  These are SELF-CONTAINED replicas with NO SDK dependency. The BufferEncodable /
//  BufferDecodable conformances are hand-written to mirror exactly how codegen emits them
//  against the #25 unified span codec:
//    * encode each stored field in declaration order into an `OutputRawSpan`; decode in the
//      same order out of a borrowed `RawSpan` threaded through `(input, at: &index)`;
//    * `encodedSize` sums each field's `encodedSize` (an UPPER BOUND on bytes written);
//    * Optional   = 1 discriminant byte (0 = none, 1 = some) then the wrapped value if some;
//    * fixed-width integer = little-endian raw bytes;
//    * String     = 1 format byte then content (compact = UTF-8 + trailing NUL);
//    * enum (raw) = the UInt8 raw value (RawRepresentable default — no hand-written witness);
//    * enum (associated values) = UInt8 discriminant then the associated values in order
//      (`encodedSize` = 1 + the selected payload's encodedSize);
//    * Collection = CollectionHeader (1 byte if count < 255, else 0xFF + 8-byte Int) then
//                   each element in order (Collection/RangeReplaceableCollection defaults).

/// Raised when an enum discriminant byte is out of range during decode. The library's own
/// `BufferDiscriminationError` is module-internal (`@usableFromInline`, not `public`), so the
/// replicas use this local equivalent wrapped in `BufferDecodingError.arbitrary` — exactly the
/// shape codegen produces for an unrecognized discriminant.
struct UnknownDiscriminant: Error, CustomStringConvertible {
    let type: String
    let code: UInt8
    var description: String { "unknown discriminant \(code) for \(type)" }
}

// MARK: - 1. PublicOrderLike — hot-path book update

/// `MarketId`-like nested fixed-width struct.
struct MarketIdLike: Equatable {
    var value: UInt64
    var flags: UInt8
}
extension MarketIdLike: BufferEncodable {
    func encode(into output: inout OutputRawSpan) {
        self.value.encode(into: &output)
        self.flags.encode(into: &output)
    }
    var encodedSize: Int {
        self.value.encodedSize + self.flags.encodedSize
    }
}
extension MarketIdLike: BufferDecodable {
    static func decode(from input: RawSpan, at index: inout Int) throws(BufferDecodingError) -> Self {
        let value: UInt64 = try .decode(from: input, at: &index)
        let flags: UInt8 = try .decode(from: input, at: &index)
        return .init(value: value, flags: flags)
    }
}

/// Order side — a simple raw-valued enum (buy / sell). Encoded as its `UInt8` raw value via the
/// RawRepresentable default conformance (no hand-written witness).
enum SideLike: UInt8, BufferEncodable, BufferDecodable {
    case buy = 0
    case sell = 1
}

/// Order type — an enum with associated values. Codegen emits a `UInt8` discriminant in
/// declaration order followed by the associated values of the selected case, in order.
enum OrderTypeLike: Equatable {
    case market
    case limit
    case stopMarket(stopPrice: Int64)
    case peg(offsetTicks: Int)
}
extension OrderTypeLike: BufferEncodable {
    func encode(into output: inout OutputRawSpan) {
        switch self {
        case .market:
            UInt8(0).encode(into: &output)
        case .limit:
            UInt8(1).encode(into: &output)
        case .stopMarket(let stopPrice):
            UInt8(2).encode(into: &output)
            stopPrice.encode(into: &output)
        case .peg(let offsetTicks):
            UInt8(3).encode(into: &output)
            offsetTicks.encode(into: &output)
        }
    }
    var encodedSize: Int {
        switch self {
        case .market:
            return 1
        case .limit:
            return 1
        case .stopMarket(let stopPrice):
            return 1 + stopPrice.encodedSize
        case .peg(let offsetTicks):
            return 1 + offsetTicks.encodedSize
        }
    }
}
extension OrderTypeLike: BufferDecodable {
    static func decode(from input: RawSpan, at index: inout Int) throws(BufferDecodingError) -> Self {
        let discriminant: UInt8 = try .decode(from: input, at: &index)
        switch discriminant {
        case 0:
            return .market
        case 1:
            return .limit
        case 2:
            let stopPrice: Int64 = try .decode(from: input, at: &index)
            return .stopMarket(stopPrice: stopPrice)
        case 3:
            let offsetTicks: Int = try .decode(from: input, at: &index)
            return .peg(offsetTicks: offsetTicks)
        case let code:
            throw .arbitrary(UnknownDiscriminant(type: "OrderTypeLike", code: code))
        }
    }
}

/// Hot-path book update. ~20 fields, the majority Optional fixed-width — the dominant real shape.
struct PublicOrderLike: Equatable {
    var identifier: UInt64
    var marketDataSource: UInt64?
    var market: MarketIdLike?
    var exchangeOrderReference: String?
    var instrument: UInt64
    var side: SideLike
    var price: Int64?
    var quantity: Int64?
    var state: UInt8?
    var count: Int?
    var priority: UInt64?
    var publicOrderTime: UInt64?
    var timeCreated: UInt64
    var timeUpdated: UInt64?
    var updatedByPlugin: UInt64?
    var updatedByModule: UInt64?
    var sourcePublicOrderRecoveryReference: String?
    var dateOfOrder: UInt32
    var type: OrderTypeLike?
}
extension PublicOrderLike: BufferEncodable {
    func encode(into output: inout OutputRawSpan) {
        self.identifier.encode(into: &output)
        self.marketDataSource.encode(into: &output)
        self.market.encode(into: &output)
        self.exchangeOrderReference.encode(into: &output)
        self.instrument.encode(into: &output)
        self.side.encode(into: &output)
        self.price.encode(into: &output)
        self.quantity.encode(into: &output)
        self.state.encode(into: &output)
        self.count.encode(into: &output)
        self.priority.encode(into: &output)
        self.publicOrderTime.encode(into: &output)
        self.timeCreated.encode(into: &output)
        self.timeUpdated.encode(into: &output)
        self.updatedByPlugin.encode(into: &output)
        self.updatedByModule.encode(into: &output)
        self.sourcePublicOrderRecoveryReference.encode(into: &output)
        self.dateOfOrder.encode(into: &output)
        self.type.encode(into: &output)
    }
    var encodedSize: Int {
        self.identifier.encodedSize
            + self.marketDataSource.encodedSize
            + self.market.encodedSize
            + self.exchangeOrderReference.encodedSize
            + self.instrument.encodedSize
            + self.side.encodedSize
            + self.price.encodedSize
            + self.quantity.encodedSize
            + self.state.encodedSize
            + self.count.encodedSize
            + self.priority.encodedSize
            + self.publicOrderTime.encodedSize
            + self.timeCreated.encodedSize
            + self.timeUpdated.encodedSize
            + self.updatedByPlugin.encodedSize
            + self.updatedByModule.encodedSize
            + self.sourcePublicOrderRecoveryReference.encodedSize
            + self.dateOfOrder.encodedSize
            + self.type.encodedSize
    }
}
extension PublicOrderLike: BufferDecodable {
    static func decode(from input: RawSpan, at index: inout Int) throws(BufferDecodingError) -> Self {
        let identifier: UInt64 = try .decode(from: input, at: &index)
        let marketDataSource: UInt64? = try .decode(from: input, at: &index)
        let market: MarketIdLike? = try .decode(from: input, at: &index)
        let exchangeOrderReference: String? = try .decode(from: input, at: &index)
        let instrument: UInt64 = try .decode(from: input, at: &index)
        let side: SideLike = try .decode(from: input, at: &index)
        let price: Int64? = try .decode(from: input, at: &index)
        let quantity: Int64? = try .decode(from: input, at: &index)
        let state: UInt8? = try .decode(from: input, at: &index)
        let count: Int? = try .decode(from: input, at: &index)
        let priority: UInt64? = try .decode(from: input, at: &index)
        let publicOrderTime: UInt64? = try .decode(from: input, at: &index)
        let timeCreated: UInt64 = try .decode(from: input, at: &index)
        let timeUpdated: UInt64? = try .decode(from: input, at: &index)
        let updatedByPlugin: UInt64? = try .decode(from: input, at: &index)
        let updatedByModule: UInt64? = try .decode(from: input, at: &index)
        let sourcePublicOrderRecoveryReference: String? = try .decode(from: input, at: &index)
        let dateOfOrder: UInt32 = try .decode(from: input, at: &index)
        let type: OrderTypeLike? = try .decode(from: input, at: &index)
        return .init(
            identifier: identifier,
            marketDataSource: marketDataSource,
            market: market,
            exchangeOrderReference: exchangeOrderReference,
            instrument: instrument,
            side: side,
            price: price,
            quantity: quantity,
            state: state,
            count: count,
            priority: priority,
            publicOrderTime: publicOrderTime,
            timeCreated: timeCreated,
            timeUpdated: timeUpdated,
            updatedByPlugin: updatedByPlugin,
            updatedByModule: updatedByModule,
            sourcePublicOrderRecoveryReference: sourcePublicOrderRecoveryReference,
            dateOfOrder: dateOfOrder,
            type: type
        )
    }
}

// MARK: - 2. ResourceLike — strings + optionals + nested

/// Semantic-version-like nested fixed-width struct.
struct SemVerLike: Equatable {
    var major: UInt16
    var minor: UInt16
    var patch: UInt16
    var preRelease: UInt16
}
extension SemVerLike: BufferEncodable {
    func encode(into output: inout OutputRawSpan) {
        self.major.encode(into: &output)
        self.minor.encode(into: &output)
        self.patch.encode(into: &output)
        self.preRelease.encode(into: &output)
    }
    var encodedSize: Int {
        self.major.encodedSize + self.minor.encodedSize
            + self.patch.encodedSize + self.preRelease.encodedSize
    }
}
extension SemVerLike: BufferDecodable {
    static func decode(from input: RawSpan, at index: inout Int) throws(BufferDecodingError) -> Self {
        let major: UInt16 = try .decode(from: input, at: &index)
        let minor: UInt16 = try .decode(from: input, at: &index)
        let patch: UInt16 = try .decode(from: input, at: &index)
        let preRelease: UInt16 = try .decode(from: input, at: &index)
        return .init(major: major, minor: minor, patch: patch, preRelease: preRelease)
    }
}

/// Nested struct mixing fixed-width fields with a (required) string — the long-sha case.
struct ResourceDataDescLike: Equatable {
    var generation: UInt64
    var partition: Int
    var offset: Int
    var totalChunks: UInt32
    var sha256: String
}
extension ResourceDataDescLike: BufferEncodable {
    func encode(into output: inout OutputRawSpan) {
        self.generation.encode(into: &output)
        self.partition.encode(into: &output)
        self.offset.encode(into: &output)
        self.totalChunks.encode(into: &output)
        self.sha256.encode(into: &output)
    }
    var encodedSize: Int {
        self.generation.encodedSize + self.partition.encodedSize
            + self.offset.encodedSize + self.totalChunks.encodedSize
            + self.sha256.encodedSize
    }
}
extension ResourceDataDescLike: BufferDecodable {
    static func decode(from input: RawSpan, at index: inout Int) throws(BufferDecodingError) -> Self {
        let generation: UInt64 = try .decode(from: input, at: &index)
        let partition: Int = try .decode(from: input, at: &index)
        let offset: Int = try .decode(from: input, at: &index)
        let totalChunks: UInt32 = try .decode(from: input, at: &index)
        let sha256: String = try .decode(from: input, at: &index)
        return .init(
            generation: generation,
            partition: partition,
            offset: offset,
            totalChunks: totalChunks,
            sha256: sha256
        )
    }
}

/// Strings + optionals + nested struct — exercises the String fastpath heavily.
struct ResourceLike: Equatable {
    var identifier: UInt64
    var state: UInt8
    var version: SemVerLike
    var sha256: String?
    var symbol: String
    var name: String?
    var originalFilesystemName: String?
    var timeCreated: UInt64
    var timeUpdated: UInt64?
    var dataDescription: ResourceDataDescLike?
}
extension ResourceLike: BufferEncodable {
    func encode(into output: inout OutputRawSpan) {
        self.identifier.encode(into: &output)
        self.state.encode(into: &output)
        self.version.encode(into: &output)
        self.sha256.encode(into: &output)
        self.symbol.encode(into: &output)
        self.name.encode(into: &output)
        self.originalFilesystemName.encode(into: &output)
        self.timeCreated.encode(into: &output)
        self.timeUpdated.encode(into: &output)
        self.dataDescription.encode(into: &output)
    }
    var encodedSize: Int {
        self.identifier.encodedSize
            + self.state.encodedSize
            + self.version.encodedSize
            + self.sha256.encodedSize
            + self.symbol.encodedSize
            + self.name.encodedSize
            + self.originalFilesystemName.encodedSize
            + self.timeCreated.encodedSize
            + self.timeUpdated.encodedSize
            + self.dataDescription.encodedSize
    }
}
extension ResourceLike: BufferDecodable {
    static func decode(from input: RawSpan, at index: inout Int) throws(BufferDecodingError) -> Self {
        let identifier: UInt64 = try .decode(from: input, at: &index)
        let state: UInt8 = try .decode(from: input, at: &index)
        let version: SemVerLike = try .decode(from: input, at: &index)
        let sha256: String? = try .decode(from: input, at: &index)
        let symbol: String = try .decode(from: input, at: &index)
        let name: String? = try .decode(from: input, at: &index)
        let originalFilesystemName: String? = try .decode(from: input, at: &index)
        let timeCreated: UInt64 = try .decode(from: input, at: &index)
        let timeUpdated: UInt64? = try .decode(from: input, at: &index)
        let dataDescription: ResourceDataDescLike? = try .decode(from: input, at: &index)
        return .init(
            identifier: identifier,
            state: state,
            version: version,
            sha256: sha256,
            symbol: symbol,
            name: name,
            originalFilesystemName: originalFilesystemName,
            timeCreated: timeCreated,
            timeUpdated: timeUpdated,
            dataDescription: dataDescription
        )
    }
}

// MARK: - 3. ComputedPropertySubscriptionLike — collection-heavy

/// Property value — an enum with associated values, every case a single payload.
enum PropertyValueLike: Equatable {
    case integer(Int)
    case decimal(Int64)
    case boolean(Bool)
    case text(String)
    case timestamp(UInt64)
    case instrument(UInt64)
}
extension PropertyValueLike: BufferEncodable {
    func encode(into output: inout OutputRawSpan) {
        switch self {
        case .integer(let v):
            UInt8(0).encode(into: &output)
            v.encode(into: &output)
        case .decimal(let v):
            UInt8(1).encode(into: &output)
            v.encode(into: &output)
        case .boolean(let v):
            UInt8(2).encode(into: &output)
            v.encode(into: &output)
        case .text(let v):
            UInt8(3).encode(into: &output)
            v.encode(into: &output)
        case .timestamp(let v):
            UInt8(4).encode(into: &output)
            v.encode(into: &output)
        case .instrument(let v):
            UInt8(5).encode(into: &output)
            v.encode(into: &output)
        }
    }
    var encodedSize: Int {
        switch self {
        case .integer(let v):
            return 1 + v.encodedSize
        case .decimal(let v):
            return 1 + v.encodedSize
        case .boolean(let v):
            return 1 + v.encodedSize
        case .text(let v):
            return 1 + v.encodedSize
        case .timestamp(let v):
            return 1 + v.encodedSize
        case .instrument(let v):
            return 1 + v.encodedSize
        }
    }
}
extension PropertyValueLike: BufferDecodable {
    static func decode(from input: RawSpan, at index: inout Int) throws(BufferDecodingError) -> Self {
        let discriminant: UInt8 = try .decode(from: input, at: &index)
        switch discriminant {
        case 0:
            return .integer(try .decode(from: input, at: &index))
        case 1:
            return .decimal(try .decode(from: input, at: &index))
        case 2:
            return .boolean(try .decode(from: input, at: &index))
        case 3:
            return .text(try .decode(from: input, at: &index))
        case 4:
            return .timestamp(try .decode(from: input, at: &index))
        case 5:
            return .instrument(try .decode(from: input, at: &index))
        case let code:
            throw .arbitrary(UnknownDiscriminant(type: "PropertyValueLike", code: code))
        }
    }
}

/// A single property: identifier + value.
struct PropertyLike: Equatable {
    var identifier: UInt64
    var value: PropertyValueLike
}
extension PropertyLike: BufferEncodable {
    func encode(into output: inout OutputRawSpan) {
        self.identifier.encode(into: &output)
        self.value.encode(into: &output)
    }
    var encodedSize: Int {
        self.identifier.encodedSize + self.value.encodedSize
    }
}
extension PropertyLike: BufferDecodable {
    static func decode(from input: RawSpan, at index: inout Int) throws(BufferDecodingError) -> Self {
        let identifier: UInt64 = try .decode(from: input, at: &index)
        let value: PropertyValueLike = try .decode(from: input, at: &index)
        return .init(identifier: identifier, value: value)
    }
}

/// Collection-heavy: a subscribed object set (`[UInt64]`) plus mixed-case settings.
struct ComputedPropertySubscriptionLike: Equatable {
    var setIdentifier: UInt64
    var objects: [UInt64]
    var settings: [PropertyLike]
}
extension ComputedPropertySubscriptionLike: BufferEncodable {
    func encode(into output: inout OutputRawSpan) {
        self.setIdentifier.encode(into: &output)
        self.objects.encode(into: &output)
        self.settings.encode(into: &output)
    }
    var encodedSize: Int {
        self.setIdentifier.encodedSize + self.objects.encodedSize + self.settings.encodedSize
    }
}
extension ComputedPropertySubscriptionLike: BufferDecodable {
    static func decode(from input: RawSpan, at index: inout Int) throws(BufferDecodingError) -> Self {
        let setIdentifier: UInt64 = try .decode(from: input, at: &index)
        let objects: [UInt64] = try .decode(from: input, at: &index)
        let settings: [PropertyLike] = try .decode(from: input, at: &index)
        return .init(setIdentifier: setIdentifier, objects: objects, settings: settings)
    }
}

// MARK: - Fixtures

enum PayloadFixtures {
    /// A realistic tick: most optionals nil, no strings, a plain `.limit` order. THE hot path.
    static func publicOrderSparse(_ i: Int) -> PublicOrderLike {
        .init(
            identifier: 0x1000_0000_0000_0000 &+ UInt64(i),
            marketDataSource: nil,
            market: nil,
            exchangeOrderReference: nil,
            instrument: 42 &+ UInt64(i & 0xff),
            side: (i & 1 == 0) ? .buy : .sell,
            price: Int64(1_000_000 &+ i),
            quantity: Int64(100 &+ (i & 0x3ff)),
            state: nil,
            count: nil,
            priority: nil,
            publicOrderTime: nil,
            timeCreated: 0x1700_0000_0000_0000 &+ UInt64(i),
            timeUpdated: nil,
            updatedByPlugin: nil,
            updatedByModule: nil,
            sourcePublicOrderRecoveryReference: nil,
            dateOfOrder: 20_260_610,
            type: .limit
        )
    }

    /// Every optional populated, both strings 16 chars, a `.stopMarket` order.
    static func publicOrderFull(_ i: Int) -> PublicOrderLike {
        .init(
            identifier: 0x1000_0000_0000_0000 &+ UInt64(i),
            marketDataSource: 7,
            market: .init(value: 0xABCD_0000 &+ UInt64(i & 0xffff), flags: 0x03),
            exchangeOrderReference: "EXREF-0123456789",        // 16 chars
            instrument: 42 &+ UInt64(i & 0xff),
            side: (i & 1 == 0) ? .buy : .sell,
            price: Int64(1_000_000 &+ i),
            quantity: Int64(100 &+ (i & 0x3ff)),
            state: 3,
            count: 12,
            priority: 9_999,
            publicOrderTime: 0x1600_0000_0000_0000 &+ UInt64(i),
            timeCreated: 0x1700_0000_0000_0000 &+ UInt64(i),
            timeUpdated: 0x1701_0000_0000_0000 &+ UInt64(i),
            updatedByPlugin: 555,
            updatedByModule: 666,
            sourcePublicOrderRecoveryReference: "RECOV-9876543210",  // 16 chars
            dateOfOrder: 20_260_610,
            type: .stopMarket(stopPrice: Int64(990_000 &+ i))
        )
    }

    static func resource(_ i: Int) -> ResourceLike {
        .init(
            identifier: 0x2000_0000_0000_0000 &+ UInt64(i),
            state: 2,
            version: .init(major: 1, minor: 4, patch: 17, preRelease: 0),
            sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",  // 64 hex
            symbol: "AAPL.OQ\(i & 1)",  // 8 chars
            name: "Apple Inc Common Stock",
            originalFilesystemName: "aapl-quote-feed.bin",
            timeCreated: 0x1700_0000_0000_0000 &+ UInt64(i),
            timeUpdated: 0x1701_0000_0000_0000 &+ UInt64(i),
            dataDescription: .init(
                generation: 3,
                partition: 7,
                offset: 1_048_576,
                totalChunks: 64,
                sha256: "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
            )
        )
    }

    /// ~8 settings of mixed PropertyValue cases.
    static func settings() -> [PropertyLike] {
        [
            .init(identifier: 1, value: .integer(42)),
            .init(identifier: 2, value: .decimal(123_456)),
            .init(identifier: 3, value: .boolean(true)),
            .init(identifier: 4, value: .text("status-ok")),
            .init(identifier: 5, value: .timestamp(0x1700_0000_0000_0000)),
            .init(identifier: 6, value: .instrument(987_654)),
            .init(identifier: 7, value: .integer(-9)),
            .init(identifier: 8, value: .text("hello-world-tag")),
        ]
    }

    static func cpSub(objectCount: Int, _ i: Int) -> ComputedPropertySubscriptionLike {
        var objects: [UInt64] = []
        objects.reserveCapacity(objectCount)
        for k in 0 ..< objectCount {
            objects.append(0x3000_0000_0000_0000 &+ UInt64(k) &+ UInt64(i))
        }
        return .init(
            setIdentifier: 0x4000_0000_0000_0000 &+ UInt64(i),
            objects: objects,
            settings: settings()
        )
    }
}

// MARK: - Round-trip helpers (measured-region bodies)

//  Two models are measured per payload shape:
//
//  OWNED (models #23 — the owning-coder baseline). Runs the `encodedSize` pass, allocates a
//  fresh `[UInt8]` via `encoded()`, then models the ByteBuffer -> Array receive copy
//  (`Array(wire)`) before decoding from that owned copy. `blackHole` keeps the decoded value
//  live. This is the full production cost of the owned path on the new API.
//
//  ZEROCOPY (the #25 win — models #24's intent). Encodes straight into a single reserved
//  `UnsafeMutableRawBufferPointer` reused across the whole batch (allocated once at
//  `msg.encodedSize`, zero mallocs in steady state), then decodes via a `RawSpan` placed over
//  exactly the written prefix — NO intermediate `[UInt8]`, NO receive copy. `blackHole` keeps
//  the decoded value live.

@inline(never)
func roundtripPayloadsOwned<T: BufferEncodable & BufferDecodable>(
    _ messages: [T]
) throws {
    for message in messages {
        // Owned encode: the `encodedSize` two-pass + a fresh allocation.
        let wire: [UInt8] = message.encoded()
        // Model the receive copy: a FRESH [UInt8] the decoder reads from (the
        // ByteBuffer -> Array copy production pays on receive).
        let received: [UInt8] = Array(wire)
        let value: T = try T.decode(received)
        blackHole(value)
    }
}

@inline(never)
func roundtripPayloadsZeroCopy<T: BufferEncodable & BufferDecodable>(
    _ messages: [T],
    region: UnsafeMutableRawBufferPointer
) throws {
    for message in messages {
        // Zero-copy encode into the reused reserved region (no allocation in steady state).
        let written: Int = message.encode(into: region)
        // Zero-copy decode: borrow exactly the written prefix as a RawSpan. No [UInt8], no
        // receive copy.
        let value: T = try region[..<written].withUnsafeBytes {
            (raw: UnsafeRawBufferPointer) throws(BufferDecodingError) -> T in
            let span: RawSpan = .init(_unsafeBytes: raw)
            return try T.decode(from: span)
        }
        blackHole(value)
    }
}

// MARK: - Registration

func registerPayloadBenchmarks() {
    let config: Benchmark.Configuration = .init(
        metrics: [.instructions, .mallocCountTotal, .wallClock],
        timeUnits: .microseconds
    )

    // Build fixture arrays ONCE (outside the measured region). 1000 messages per iteration so
    // the per-message work dominates the loop overhead.
    let messageCount: Int = 1_000

    /// Registers an OWNED and a ZEROCOPY benchmark for one fixture array. The zero-copy region is
    /// sized to the largest message in the batch and reused across every message and iteration.
    func register<T: BufferEncodable & BufferDecodable & Equatable>(
        _ name: String,
        _ messages: [T]
    ) {
        precondition(debugRoundtripOK(messages[0]), "\(name) roundtrip mismatch")

        Benchmark.init("\(name) owned", configuration: config) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                try roundtripPayloadsOwned(messages)
            }
        }

        Benchmark.init("\(name) zerocopy", configuration: config) { benchmark in
            let capacity: Int = messages.lazy.map(\.encodedSize).max() ?? 0
            let region: UnsafeMutableRawBufferPointer = .allocate(
                byteCount: capacity,
                alignment: MemoryLayout<UInt64>.alignment
            )
            defer { region.deallocate() }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                try roundtripPayloadsZeroCopy(messages, region: region)
            }
        }
    }

    // -- PublicOrderLike sparse (the true hot path) --
    register("PublicOrder sparse", (0 ..< messageCount).map(PayloadFixtures.publicOrderSparse))

    // -- PublicOrderLike full (every optional populated, two 16-char strings) --
    register("PublicOrder full", (0 ..< messageCount).map(PayloadFixtures.publicOrderFull))

    // -- ResourceLike (strings + optionals + nested) --
    register("Resource", (0 ..< messageCount).map(PayloadFixtures.resource))

    // -- ComputedPropertySubscriptionLike across object counts (Big-O slope) --
    //  Fewer messages per iteration for the large object counts so total work per iteration
    //  stays bounded; per-element instructions are derived from the slope across counts.
    for objectCount in [10, 100, 1_000, 10_000] {
        let msgs: Int = objectCount >= 1_000 ? 50 : messageCount
        register(
            "CPSub objects=\(objectCount)",
            (0 ..< msgs).map { PayloadFixtures.cpSub(objectCount: objectCount, $0) }
        )
    }
}

/// A quick round-trip validation used at fixture-build time so we KNOW encode/decode agree
/// before measuring. Returns true iff the decoded value equals the original (exercising both
/// the owned and zero-copy paths).
func debugRoundtripOK<T: BufferEncodable & BufferDecodable & Equatable>(
    _ message: T
) -> Bool {
    do {
        // Owned path.
        let bytes: [UInt8] = message.encoded()
        let ownedDecoded: T = try T.decode(bytes)

        // Zero-copy path.
        let region: UnsafeMutableRawBufferPointer = .allocate(
            byteCount: message.encodedSize,
            alignment: MemoryLayout<UInt64>.alignment
        )
        defer { region.deallocate() }
        let written: Int = message.encode(into: region)
        let zeroCopyDecoded: T = try region[..<written].withUnsafeBytes {
            (raw: UnsafeRawBufferPointer) throws(BufferDecodingError) -> T in
            let span: RawSpan = .init(_unsafeBytes: raw)
            return try T.decode(from: span)
        }

        return ownedDecoded == message && zeroCopyDecoded == message
    } catch {
        return false
    }
}
