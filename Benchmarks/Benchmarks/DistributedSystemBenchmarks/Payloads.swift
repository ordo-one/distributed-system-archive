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
//  These are SELF-CONTAINED replicas with NO SDK dependency, and their `Transferable`
//  conformances are written the way a hand-written composite conforms in DistributedABI 8.0:
//    * a struct writes each stored field in declaration order through `append(framed:)`, and
//      reads it back in the same order through `take(framed:)`: a field whose type has a
//      fixed size is packed, any other is preceded by its ULEB128 length;
//    * a struct whose fields all have a fixed size states the sum as its own fixed size;
//    * Optional   = 1 discriminant byte (0 = none, 1 = some) then the wrapped value if some;
//    * fixed-width integer = little-endian raw bytes;
//    * String     = the UTF-8 bytes, framed by the container;
//    * enum (raw) = the UInt8 raw value, through the library’s `RawRepresentable` default;
//    * enum (associated values) = UInt8 discriminant then the payload, which its container
//      frames, as `Optional` and `Result` do;
//    * Collection = ULEB128 count then each element (packed or framed, as above).
//
//  In production these shapes are SBE rows, which lend their bytes unchanged; the replicas
//  measure what a composite that does serialize costs.

// MARK: - 1. PublicOrderLike — hot-path book update

/// `MarketId`-like nested fixed-width struct.
struct MarketIdLike: Equatable {
    var value: UInt64
    var flags: UInt8
}
extension MarketIdLike: Transferable {
    static var fixedTransferSize: Int? { 9 }
    var transferSize: Int { 9 }

    func transfer(into output: inout OutputRawSpan) {
        output.append(framed: self.value)
        output.append(framed: self.flags)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        let value: UInt64 = try input.take(framed: UInt64.self)
        let flags: UInt8 = try input.take(framed: UInt8.self)
        self.init(value: value, flags: flags)
    }
}

/// Order side — a simple raw-valued enum (buy / sell). Travels as its `UInt8` raw value.
enum SideLike: UInt8, Transferable {
    case buy = 0
    case sell = 1
}

/// Order type — an enum with associated values: a `UInt8` discriminant in declaration order
/// followed by the associated value of the selected case.
enum OrderTypeLike: Equatable {
    case market
    case limit
    case stopMarket(stopPrice: Int64)
    case peg(offsetTicks: Int)
}
extension OrderTypeLike: Transferable {
    var transferSize: Int {
        switch self {
        case .market, .limit: 1
        case .stopMarket: 9
        case .peg: 9
        }
    }

    func transfer(into output: inout OutputRawSpan) {
        switch self {
        case .market:
            output.append(0)
        case .limit:
            output.append(1)
        case .stopMarket(let stopPrice):
            output.append(2)
            stopPrice.transfer(into: &output)
        case .peg(let offsetTicks):
            output.append(3)
            offsetTicks.transfer(into: &output)
        }
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        switch try input.take(UInt8.self) {
        case 0: self = .market
        case 1: self = .limit
        case 2: self = .stopMarket(stopPrice: try .init(transferring: &input))
        case 3: self = .peg(offsetTicks: try .init(transferring: &input))
        case let code: throw .init(.discriminant(.init(code)))
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
extension PublicOrderLike: Transferable {
    var transferSize: Int {
        self.identifier.framedTransferSize
            + self.marketDataSource.framedTransferSize
            + self.market.framedTransferSize
            + self.exchangeOrderReference.framedTransferSize
            + self.instrument.framedTransferSize
            + self.side.framedTransferSize
            + self.price.framedTransferSize
            + self.quantity.framedTransferSize
            + self.state.framedTransferSize
            + self.count.framedTransferSize
            + self.priority.framedTransferSize
            + self.publicOrderTime.framedTransferSize
            + self.timeCreated.framedTransferSize
            + self.timeUpdated.framedTransferSize
            + self.updatedByPlugin.framedTransferSize
            + self.updatedByModule.framedTransferSize
            + self.sourcePublicOrderRecoveryReference.framedTransferSize
            + self.dateOfOrder.framedTransferSize
            + self.type.framedTransferSize
    }

    func transfer(into output: inout OutputRawSpan) {
        output.append(framed: self.identifier)
        output.append(framed: self.marketDataSource)
        output.append(framed: self.market)
        output.append(framed: self.exchangeOrderReference)
        output.append(framed: self.instrument)
        output.append(framed: self.side)
        output.append(framed: self.price)
        output.append(framed: self.quantity)
        output.append(framed: self.state)
        output.append(framed: self.count)
        output.append(framed: self.priority)
        output.append(framed: self.publicOrderTime)
        output.append(framed: self.timeCreated)
        output.append(framed: self.timeUpdated)
        output.append(framed: self.updatedByPlugin)
        output.append(framed: self.updatedByModule)
        output.append(framed: self.sourcePublicOrderRecoveryReference)
        output.append(framed: self.dateOfOrder)
        output.append(framed: self.type)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(
            identifier: try input.take(framed: UInt64.self),
            marketDataSource: try input.take(framed: UInt64?.self),
            market: try input.take(framed: MarketIdLike?.self),
            exchangeOrderReference: try input.take(framed: String?.self),
            instrument: try input.take(framed: UInt64.self),
            side: try input.take(framed: SideLike.self),
            price: try input.take(framed: Int64?.self),
            quantity: try input.take(framed: Int64?.self),
            state: try input.take(framed: UInt8?.self),
            count: try input.take(framed: Int?.self),
            priority: try input.take(framed: UInt64?.self),
            publicOrderTime: try input.take(framed: UInt64?.self),
            timeCreated: try input.take(framed: UInt64.self),
            timeUpdated: try input.take(framed: UInt64?.self),
            updatedByPlugin: try input.take(framed: UInt64?.self),
            updatedByModule: try input.take(framed: UInt64?.self),
            sourcePublicOrderRecoveryReference: try input.take(framed: String?.self),
            dateOfOrder: try input.take(framed: UInt32.self),
            type: try input.take(framed: OrderTypeLike?.self)
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
extension SemVerLike: Transferable {
    static var fixedTransferSize: Int? { 8 }
    var transferSize: Int { 8 }

    func transfer(into output: inout OutputRawSpan) {
        output.append(framed: self.major)
        output.append(framed: self.minor)
        output.append(framed: self.patch)
        output.append(framed: self.preRelease)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(
            major: try input.take(framed: UInt16.self),
            minor: try input.take(framed: UInt16.self),
            patch: try input.take(framed: UInt16.self),
            preRelease: try input.take(framed: UInt16.self)
        )
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
extension ResourceDataDescLike: Transferable {
    var transferSize: Int {
        self.generation.framedTransferSize
            + self.partition.framedTransferSize
            + self.offset.framedTransferSize
            + self.totalChunks.framedTransferSize
            + self.sha256.framedTransferSize
    }

    func transfer(into output: inout OutputRawSpan) {
        output.append(framed: self.generation)
        output.append(framed: self.partition)
        output.append(framed: self.offset)
        output.append(framed: self.totalChunks)
        output.append(framed: self.sha256)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(
            generation: try input.take(framed: UInt64.self),
            partition: try input.take(framed: Int.self),
            offset: try input.take(framed: Int.self),
            totalChunks: try input.take(framed: UInt32.self),
            sha256: try input.take(framed: String.self)
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
extension ResourceLike: Transferable {
    var transferSize: Int {
        self.identifier.framedTransferSize
            + self.state.framedTransferSize
            + self.version.framedTransferSize
            + self.sha256.framedTransferSize
            + self.symbol.framedTransferSize
            + self.name.framedTransferSize
            + self.originalFilesystemName.framedTransferSize
            + self.timeCreated.framedTransferSize
            + self.timeUpdated.framedTransferSize
            + self.dataDescription.framedTransferSize
    }

    func transfer(into output: inout OutputRawSpan) {
        output.append(framed: self.identifier)
        output.append(framed: self.state)
        output.append(framed: self.version)
        output.append(framed: self.sha256)
        output.append(framed: self.symbol)
        output.append(framed: self.name)
        output.append(framed: self.originalFilesystemName)
        output.append(framed: self.timeCreated)
        output.append(framed: self.timeUpdated)
        output.append(framed: self.dataDescription)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(
            identifier: try input.take(framed: UInt64.self),
            state: try input.take(framed: UInt8.self),
            version: try input.take(framed: SemVerLike.self),
            sha256: try input.take(framed: String?.self),
            symbol: try input.take(framed: String.self),
            name: try input.take(framed: String?.self),
            originalFilesystemName: try input.take(framed: String?.self),
            timeCreated: try input.take(framed: UInt64.self),
            timeUpdated: try input.take(framed: UInt64?.self),
            dataDescription: try input.take(framed: ResourceDataDescLike?.self)
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
extension PropertyValueLike: Transferable {
    var transferSize: Int {
        switch self {
        case .integer(let self): 1 + self.transferSize
        case .decimal(let self): 1 + self.transferSize
        case .boolean(let self): 1 + self.transferSize
        case .text(let self): 1 + self.transferSize
        case .timestamp(let self): 1 + self.transferSize
        case .instrument(let self): 1 + self.transferSize
        }
    }

    func transfer(into output: inout OutputRawSpan) {
        switch self {
        case .integer(let self):
            output.append(0)
            self.transfer(into: &output)
        case .decimal(let self):
            output.append(1)
            self.transfer(into: &output)
        case .boolean(let self):
            output.append(2)
            self.transfer(into: &output)
        case .text(let self):
            output.append(3)
            self.transfer(into: &output)
        case .timestamp(let self):
            output.append(4)
            self.transfer(into: &output)
        case .instrument(let self):
            output.append(5)
            self.transfer(into: &output)
        }
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        switch try input.take(UInt8.self) {
        case 0: self = .integer(try .init(transferring: &input))
        case 1: self = .decimal(try .init(transferring: &input))
        case 2: self = .boolean(try .init(transferring: &input))
        case 3: self = .text(try .init(transferring: &input))
        case 4: self = .timestamp(try .init(transferring: &input))
        case 5: self = .instrument(try .init(transferring: &input))
        case let code: throw .init(.discriminant(.init(code)))
        }
    }
}

/// A single property: identifier + value.
struct PropertyLike: Equatable {
    var identifier: UInt64
    var value: PropertyValueLike
}
extension PropertyLike: Transferable {
    var transferSize: Int {
        self.identifier.framedTransferSize + self.value.framedTransferSize
    }

    func transfer(into output: inout OutputRawSpan) {
        output.append(framed: self.identifier)
        output.append(framed: self.value)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(
            identifier: try input.take(framed: UInt64.self),
            value: try input.take(framed: PropertyValueLike.self)
        )
    }
}

/// Collection-heavy: a subscribed object set (`[UInt64]`) plus mixed-case settings.
struct ComputedPropertySubscriptionLike: Equatable {
    var setIdentifier: UInt64
    var objects: [UInt64]
    var settings: [PropertyLike]
}
extension ComputedPropertySubscriptionLike: Transferable {
    var transferSize: Int {
        self.setIdentifier.framedTransferSize
            + self.objects.framedTransferSize
            + self.settings.framedTransferSize
    }

    func transfer(into output: inout OutputRawSpan) {
        output.append(framed: self.setIdentifier)
        output.append(framed: self.objects)
        output.append(framed: self.settings)
    }
    init(transferring input: inout TransferReader) throws(TransferError) {
        self.init(
            setIdentifier: try input.take(framed: UInt64.self),
            objects: try input.take(framed: [UInt64].self),
            settings: try input.take(framed: [PropertyLike].self)
        )
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
            sha256: """
            0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
            """,  // 64 hex
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

//  The measured region models the 8.0 transport path: the message is sized from
//  `transferSize`, written straight into one reused frame buffer (the send, no intermediate
//  copy), and read back from that buffer through a borrowed reader (the receive, no decoder
//  copy). `blackHole` keeps the decoded value live. The 7.x suite also measured “nocopy”
//  variants that left out its two buffer copies; 8.0 has neither copy, so they are gone.

@inline(never) func roundtripPayloads<Message>(
    _ messages: [Message],
    frame: UnsafeMutableRawBufferPointer
) throws(TransferError) where Message: Transferable {
    for message: Message in messages {
        precondition(message.transferSize <= frame.count, "frame too small")
        var output: OutputRawSpan = .init(buffer: frame, initializedCount: 0)
        message.transfer(into: &output)
        do {
            var input: TransferReader = .init(output.bytes)
            let value: Message = try .init(transferring: &input)
            try input.finish()
            blackHole(value)
        }
        _ = output.finalize(for: frame)
    }
}

// MARK: - Registration

func registerPayloadBenchmarks() {
    let config: Benchmark.Configuration = .init(metrics: .default, timeUnits: .microseconds)

    // Build fixture arrays ONCE (outside the measured region). 1000 messages per iteration so
    // the per-message work dominates the loop overhead.
    let messageCount: Int = 1_000

    func register<Message>(_ name: String, _ messages: [Message], frame capacity: Int)
        where Message: Transferable & Equatable {
        precondition(debugRoundtripOK(messages[0]), "\(name) roundtrip mismatch")
        Benchmark.init(name, configuration: config) { benchmark in
            let frame: UnsafeMutableRawBufferPointer = .allocate(
                byteCount: capacity,
                alignment: 16
            )
            defer {
                frame.deallocate()
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                try roundtripPayloads(messages, frame: frame)
            }
        }
    }

    // -- PublicOrderLike sparse (the true hot path) --
    register(
        "PublicOrder sparse",
        (0 ..< messageCount).map(PayloadFixtures.publicOrderSparse),
        frame: 256
    )
    // -- PublicOrderLike full (every optional populated, two 16-char strings) --
    register(
        "PublicOrder full",
        (0 ..< messageCount).map(PayloadFixtures.publicOrderFull),
        frame: 256
    )
    // -- ResourceLike (strings + optionals + nested) --
    register("Resource", (0 ..< messageCount).map(PayloadFixtures.resource), frame: 512)

    // -- ComputedPropertySubscriptionLike across object counts (Big-O slope) --
    //  Fewer messages per iteration for the large object counts so total work per iteration
    //  stays bounded; per-element instructions are derived from the slope across counts.
    for objectCount: Int in [10, 100, 1_000, 10_000] {
        let messages: Int = objectCount >= 1_000 ? 50 : 200
        register(
            "CPSub objects=\(objectCount)",
            (0 ..< messages).map { PayloadFixtures.cpSub(objectCount: objectCount, $0) },
            frame: objectCount * 9 + 256
        )
    }
}

/// A quick round-trip validation used at fixture-build time so we KNOW the conformance agrees
/// with itself, and writes exactly the bytes it states, before measuring.
func debugRoundtripOK<Message>(_ message: Message) -> Bool
    where Message: Transferable & Equatable {
    let bytes: [UInt8] = .init(transferring: message)
    guard bytes.count == message.transferSize else {
        return false
    }
    do {
        return try Message.decode(bytes) == message
    } catch {
        return false
    }
}
