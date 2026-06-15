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
//  BufferDecodable conformances are hand-written to mirror exactly how codegen emits them:
//    * encode each stored field in declaration order; decode in the same order;
//    * Optional   = 1 discriminant byte (0 = none, 1 = some) then the wrapped value if some;
//    * fixed-width integer = little-endian raw bytes;
//    * String     = 1 format byte then content (compact = UTF-8 + trailing NUL);
//    * enum (raw) = the UInt8 raw value;
//    * enum (associated values) = UInt8 discriminant then the associated values in order;
//    * Collection = CollectionHeader (1 byte if count < 255, else 0xFF + 8-byte Int) then
//                   each element in order.
//
//  All three types use `BufferDecodingError` as their `DeserializationError` and `Never` as
//  their `SerializationError` is NOT possible (String/Collection conformances are non-throwing
//  but the protocol requires an error type) — so we follow the library's own convention and
//  declare `BufferDecodingError` for decode and let encode be non-throwing where every field is
//  non-throwing. To keep the conformances uniform and codegen-faithful we mark `encode` as
//  `throws(BufferDecodingError)`-free (non-throwing) since none of these field types throw on
//  encode; decode uses `BufferDecodingError`.

// MARK: - Shared helpers (codegen-faithful field encode/decode)

//  NOTE: every field's `encode` here is non-throwing (integers, Bool, String, Optional of those,
//  and Collections of those are all non-throwing on the encode side in this library), so the
//  message-level `encode` is non-throwing too. Decode is `throws(BufferDecodingError)`.

/// Raised when an enum discriminant byte is out of range during decode. The library's own
/// `BufferDiscriminationError` is module-internal, so the replicas use this local equivalent
/// wrapped in `BufferDecodingError.arbitrary` — exactly the shape codegen produces for an
/// unrecognized discriminant.
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
    func encode(to output: inout BufferEncoder) {
        self.value.encode(to: &output)
        self.flags.encode(to: &output)
    }
}
extension MarketIdLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let value: UInt64 = try .decode(from: &input)
        let flags: UInt8 = try .decode(from: &input)
        return .init(value: value, flags: flags)
    }
}

/// Order side — a simple raw-valued enum (buy / sell). Encoded as its `UInt8` raw value.
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
    func encode(to output: inout BufferEncoder) {
        switch self {
        case .market:
            UInt8(0).encode(to: &output)
        case .limit:
            UInt8(1).encode(to: &output)
        case .stopMarket(let stopPrice):
            UInt8(2).encode(to: &output)
            stopPrice.encode(to: &output)
        case .peg(let offsetTicks):
            UInt8(3).encode(to: &output)
            offsetTicks.encode(to: &output)
        }
    }
}
extension OrderTypeLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let discriminant: UInt8 = try .decode(from: &input)
        switch discriminant {
        case 0:
            return .market
        case 1:
            return .limit
        case 2:
            let stopPrice: Int64 = try .decode(from: &input)
            return .stopMarket(stopPrice: stopPrice)
        case 3:
            let offsetTicks: Int = try .decode(from: &input)
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
    func encode(to output: inout BufferEncoder) {
        self.identifier.encode(to: &output)
        self.marketDataSource.encode(to: &output)
        self.market.encode(to: &output)
        self.exchangeOrderReference.encode(to: &output)
        self.instrument.encode(to: &output)
        self.side.encode(to: &output)
        self.price.encode(to: &output)
        self.quantity.encode(to: &output)
        self.state.encode(to: &output)
        self.count.encode(to: &output)
        self.priority.encode(to: &output)
        self.publicOrderTime.encode(to: &output)
        self.timeCreated.encode(to: &output)
        self.timeUpdated.encode(to: &output)
        self.updatedByPlugin.encode(to: &output)
        self.updatedByModule.encode(to: &output)
        self.sourcePublicOrderRecoveryReference.encode(to: &output)
        self.dateOfOrder.encode(to: &output)
        self.type.encode(to: &output)
    }
}
extension PublicOrderLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let identifier: UInt64 = try .decode(from: &input)
        let marketDataSource: UInt64? = try .decode(from: &input)
        let market: MarketIdLike? = try .decode(from: &input)
        let exchangeOrderReference: String? = try .decode(from: &input)
        let instrument: UInt64 = try .decode(from: &input)
        let side: SideLike = try .decode(from: &input)
        let price: Int64? = try .decode(from: &input)
        let quantity: Int64? = try .decode(from: &input)
        let state: UInt8? = try .decode(from: &input)
        let count: Int? = try .decode(from: &input)
        let priority: UInt64? = try .decode(from: &input)
        let publicOrderTime: UInt64? = try .decode(from: &input)
        let timeCreated: UInt64 = try .decode(from: &input)
        let timeUpdated: UInt64? = try .decode(from: &input)
        let updatedByPlugin: UInt64? = try .decode(from: &input)
        let updatedByModule: UInt64? = try .decode(from: &input)
        let sourcePublicOrderRecoveryReference: String? = try .decode(from: &input)
        let dateOfOrder: UInt32 = try .decode(from: &input)
        let type: OrderTypeLike? = try .decode(from: &input)
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
    func encode(to output: inout BufferEncoder) {
        self.major.encode(to: &output)
        self.minor.encode(to: &output)
        self.patch.encode(to: &output)
        self.preRelease.encode(to: &output)
    }
}
extension SemVerLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let major: UInt16 = try .decode(from: &input)
        let minor: UInt16 = try .decode(from: &input)
        let patch: UInt16 = try .decode(from: &input)
        let preRelease: UInt16 = try .decode(from: &input)
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
    func encode(to output: inout BufferEncoder) {
        self.generation.encode(to: &output)
        self.partition.encode(to: &output)
        self.offset.encode(to: &output)
        self.totalChunks.encode(to: &output)
        self.sha256.encode(to: &output)
    }
}
extension ResourceDataDescLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let generation: UInt64 = try .decode(from: &input)
        let partition: Int = try .decode(from: &input)
        let offset: Int = try .decode(from: &input)
        let totalChunks: UInt32 = try .decode(from: &input)
        let sha256: String = try .decode(from: &input)
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
    func encode(to output: inout BufferEncoder) {
        self.identifier.encode(to: &output)
        self.state.encode(to: &output)
        self.version.encode(to: &output)
        self.sha256.encode(to: &output)
        self.symbol.encode(to: &output)
        self.name.encode(to: &output)
        self.originalFilesystemName.encode(to: &output)
        self.timeCreated.encode(to: &output)
        self.timeUpdated.encode(to: &output)
        self.dataDescription.encode(to: &output)
    }
}
extension ResourceLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let identifier: UInt64 = try .decode(from: &input)
        let state: UInt8 = try .decode(from: &input)
        let version: SemVerLike = try .decode(from: &input)
        let sha256: String? = try .decode(from: &input)
        let symbol: String = try .decode(from: &input)
        let name: String? = try .decode(from: &input)
        let originalFilesystemName: String? = try .decode(from: &input)
        let timeCreated: UInt64 = try .decode(from: &input)
        let timeUpdated: UInt64? = try .decode(from: &input)
        let dataDescription: ResourceDataDescLike? = try .decode(from: &input)
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
    func encode(to output: inout BufferEncoder) {
        switch self {
        case .integer(let v):
            UInt8(0).encode(to: &output)
            v.encode(to: &output)
        case .decimal(let v):
            UInt8(1).encode(to: &output)
            v.encode(to: &output)
        case .boolean(let v):
            UInt8(2).encode(to: &output)
            v.encode(to: &output)
        case .text(let v):
            UInt8(3).encode(to: &output)
            v.encode(to: &output)
        case .timestamp(let v):
            UInt8(4).encode(to: &output)
            v.encode(to: &output)
        case .instrument(let v):
            UInt8(5).encode(to: &output)
            v.encode(to: &output)
        }
    }
}
extension PropertyValueLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let discriminant: UInt8 = try .decode(from: &input)
        switch discriminant {
        case 0:
            return .integer(try .decode(from: &input))
        case 1:
            return .decimal(try .decode(from: &input))
        case 2:
            return .boolean(try .decode(from: &input))
        case 3:
            return .text(try .decode(from: &input))
        case 4:
            return .timestamp(try .decode(from: &input))
        case 5:
            return .instrument(try .decode(from: &input))
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
    func encode(to output: inout BufferEncoder) {
        self.identifier.encode(to: &output)
        self.value.encode(to: &output)
    }
}
extension PropertyLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let identifier: UInt64 = try .decode(from: &input)
        let value: PropertyValueLike = try .decode(from: &input)
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
    func encode(to output: inout BufferEncoder) {
        self.setIdentifier.encode(to: &output)
        self.objects.encode(to: &output)
        self.settings.encode(to: &output)
    }
}
extension ComputedPropertySubscriptionLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let setIdentifier: UInt64 = try .decode(from: &input)
        let objects: [UInt64] = try .decode(from: &input)
        let settings: [PropertyLike] = try .decode(from: &input)
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

//  The measured region models the FULL production cost: encode each message into ONE reused
//  encoder, copy the encoder output into a reused `[UInt8]` wire buffer (the send copy), then
//  decode from a FRESH `[UInt8]` copy of those bytes (the ByteBuffer -> Array receive copy that
//  production pays on the wire). `blackHole` keeps the decoded value live.

@inline(never)
func roundtripPayloads<T: BufferEncodable & BufferDecodable>(
    _ messages: [T],
    wire: inout [UInt8]
) throws where T.SerializationError == Never {
    for message in messages {
        // Reuse the wire buffer's backing storage across messages with a genuine
        // zero-copy hand-off: clear it (keeping capacity), move it into the encoder,
        // drop our reference so the encoder's buffer is uniquely owned (no COW copy
        // on the first append), encode in place, then reclaim it via `finalize()`
        // with its grown capacity intact. Steady state does zero encoder reallocs.
        wire.removeAll(keepingCapacity: true)
        var encoder: BufferEncoder = .init(preallocated: wire)
        wire = []
        try message.encode(to: &encoder)
        wire = encoder.storage
        // model the receive copy: a FRESH [UInt8] the decoder reads from (the
        // ByteBuffer -> Array copy production pays on receive).
        let received: [UInt8] = Array(wire)
        var decoder: BufferDecoder = .init(received[...])
        let value: T = try .decode(from: &decoder)
        blackHole(value)
    }
}

//  NoCopy variant: feed `encoder.output` straight into the decoder, with NO send copy and NO
//  receive copy. Isolates the cost of the two production buffer copies (copy − nocopy delta).
@inline(never)
func roundtripPayloadsNoCopy<T: BufferEncodable & BufferDecodable>(
    _ messages: [T]
) throws where T.SerializationError == Never {
    for message in messages {
        var encoder: BufferEncoder = .init(capacity: 256)
        try message.encode(to: &encoder)
        var decoder: BufferDecoder = .init(encoder.output)
        let value: T = try .decode(from: &decoder)
        blackHole(value)
    }
}

// MARK: - Registration

func registerPayloadBenchmarks() {
    let config: Benchmark.Configuration = .init(metrics: .default, timeUnits: .microseconds)

    // Build fixture arrays ONCE (outside the measured region). 1000 messages per iteration so
    // the per-message work dominates the loop overhead.
    let messageCount: Int = 1_000

    // -- PublicOrderLike sparse (the true hot path) --
    let sparse: [PublicOrderLike] = (0 ..< messageCount).map(PayloadFixtures.publicOrderSparse)
    precondition(debugRoundtripOK(sparse[0]), "PublicOrder sparse roundtrip mismatch")

    Benchmark.init("PublicOrder sparse", configuration: config) { benchmark in
        var wire: [UInt8] = []
        wire.reserveCapacity(256)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try roundtripPayloads(sparse, wire: &wire)
        }
    }

    Benchmark.init("PublicOrder sparse nocopy", configuration: config) { benchmark in
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try roundtripPayloadsNoCopy(sparse)
        }
    }

    // -- PublicOrderLike full (every optional populated, two 16-char strings) --
    let full: [PublicOrderLike] = (0 ..< messageCount).map(PayloadFixtures.publicOrderFull)
    precondition(debugRoundtripOK(full[0]), "PublicOrder full roundtrip mismatch")

    Benchmark.init("PublicOrder full", configuration: config) { benchmark in
        var wire: [UInt8] = []
        wire.reserveCapacity(256)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try roundtripPayloads(full, wire: &wire)
        }
    }

    Benchmark.init("PublicOrder full nocopy", configuration: config) { benchmark in
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try roundtripPayloadsNoCopy(full)
        }
    }

    // -- ResourceLike (strings + optionals + nested) --
    let resources: [ResourceLike] = (0 ..< messageCount).map(PayloadFixtures.resource)
    precondition(debugRoundtripOK(resources[0]), "Resource roundtrip mismatch")

    Benchmark.init("Resource", configuration: config) { benchmark in
        var wire: [UInt8] = []
        wire.reserveCapacity(512)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try roundtripPayloads(resources, wire: &wire)
        }
    }

    // -- ComputedPropertySubscriptionLike across object counts (Big-O slope) --
    //  Fewer messages per iteration for the large object counts so total work per iteration
    //  stays bounded; per-element instructions are derived from the slope across counts.
    for objectCount in [10, 100, 1_000, 10_000] {
        let msgs: Int = objectCount >= 1_000 ? 50 : 200
        let cpsubs: [ComputedPropertySubscriptionLike] =
            (0 ..< msgs).map { PayloadFixtures.cpSub(objectCount: objectCount, $0) }
        precondition(debugRoundtripOK(cpsubs[0]), "CPSub roundtrip mismatch")

        let cap: Int = objectCount * 9 + 256
        Benchmark.init("CPSub objects=\(objectCount)", configuration: config) { benchmark in
            var wire: [UInt8] = []
            wire.reserveCapacity(cap)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                try roundtripPayloads(cpsubs, wire: &wire)
            }
        }
    }
}

/// A quick round-trip validation used at fixture-build time so we KNOW encode/decode agree
/// before measuring. Returns true iff the decoded value equals the original.
func debugRoundtripOK<T: BufferEncodable & BufferDecodable & Equatable>(
    _ message: T
) -> Bool where T.SerializationError == Never {
    do {
        var encoder: BufferEncoder = .init(capacity: 256)
        try message.encode(to: &encoder)
        let bytes: [UInt8] = Array(encoder.output)
        var decoder: BufferDecoder = .init(bytes[...])
        let decoded: T = try .decode(from: &decoder)
        try decoder.finish()
        return decoded == message
    } catch {
        return false
    }
}
