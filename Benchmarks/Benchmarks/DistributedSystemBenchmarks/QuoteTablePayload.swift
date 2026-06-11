import Benchmark
import DistributedABI
import Foundation

//  TRADING-QUOTER BIG PAYLOAD: Codable/JSON (today) vs DistributedABI (#23 + #24).
//
//  The plugin-trading-quoter Engine -> Quoter big payload is `QuoteTables`, the argument to
//      distributed func quoteTable(_ table: QuoteTables) async throws
//  (real type: ~/GitHub/plugin-trading-quoter/Sources/QuoterEndpoints/Sources/QuoterEndpoints.swift:161;
//   distributed func: same file line 448, and Sources/Quoter/QuoterPlugin+Endpoint.swift:27).
//
//  TODAY that payload is serialized via Swift `Codable` -> JSON: the plugin host
//  (PluginSystem.SerializationRequirement = Codable) boxes each distributed-call argument with
//  `JSONEncoder` on the Engine side and `JSONDecoder` on the Quoter side. JSON renders every
//  integer field as ASCII digits, so a `[Int64]` of N prices becomes N decimal strings + commas.
//
//  This file quantifies the gain of moving that ONE payload to DistributedABI:
//    * baseline  — Foundation `JSONEncoder().encode` / `JSONDecoder().decode` (the real path).
//    * #23       — the [UInt8]-backed `BufferEncoder` + `ArraySlice` `BufferDecoder`. Encode
//                  stages into an owned [UInt8] (the send copy); decode reads a FRESH [UInt8]
//                  (the ByteBuffer -> Array receive copy production pays).
//    * #24       — the zero-copy `SpanEncoder` (writes straight into a reserved region, no
//                  staging / no send copy) + `SpanDecoder` (decodes from borrowed memory, no
//                  receive copy).
//
//  REPLICA SPEC (self-contained, NO SDK dependency). The real types use OrdoEssentials
//  FixedPointDecimal/Price/Quantity (Int64-backed), InstrumentIdentifier (UInt64), DeltaStatus
//  (UInt8 enum), and ContiguousArray. We model FixedPointDecimal/Price as Int64, identifiers as
//  UInt64, DeltaStatus as a UInt8 raw enum, and use plain `Array` instead of `ContiguousArray` —
//  the wire form is IDENTICAL (both encode CollectionHeader + elements; DistributedABI ships an
//  `Array` conformance) and JSON serializes both as a flat number array.
//
//  Fixtures are built ONCE outside any measured region with a deterministic SplitMix64 PRNG, and
//  match the project's own HotPathBenchmark params: N instruments (3000 and 5000), windowTicks =
//  200, per-instrument-per-side price-range count = (rng % 8) + 3, transitionsPerTick = N / 10.
//  Correctness (round-trip per system + #23-bytes == #24-bytes) is asserted before any benchmark.

// MARK: - Replica types (model of QuoteTables, NO SDK dependency)

/// Model of `QuoterEndpoints.DeltaStatus` (a `UInt8` raw enum). RawRepresentable, so the
/// DistributedABI conformances forward to the `UInt8` raw value; `Codable` synthesizes the same.
enum DeltaStatusLike: UInt8, Codable, Equatable {
    case positive, negative, neutral, unknown
}

/// Model of `QuoterEndpoints.QuoteTable` (QuoterEndpoints.swift:118). FixedPointDecimal -> Int64,
/// Price -> Int64, CSR price layout (`prices` flat, `priceOffsets` = N+1).
struct QuoteTableLike: Codable, Equatable {
    var windowLow: Int64
    var windowHigh: Int64
    var baseTickSize: Int64
    var prices: [Int64]
    var priceOffsets: [Int32]
}

/// Model of `QuoterEndpoints.TransitionIndex` (QuoterEndpoints.swift:108). CSR transition index.
struct TransitionIndexLike: Codable, Equatable {
    var offsets: [Int32]
    var entries: [UInt16]
}

/// Model of `QuoterEndpoints.QuoteTables` (QuoterEndpoints.swift:161) — the `quoteTable(_:)`
/// argument. baseInstrument: InstrumentIdentifier -> UInt64; deltaStatus flat layout
/// [instrumentIndex * windowTicks + tickOffset].
struct QuoteTablesLike: Codable, Equatable {
    var baseInstrument: UInt64
    var bidTable: QuoteTableLike
    var askTable: QuoteTableLike
    var bidTransitionIndex: TransitionIndexLike
    var askTransitionIndex: TransitionIndexLike
    var deltaStatus: [UInt8]
    var windowTicks: Int
    var windowGeneration: UInt64
    var settingsGeneration: UInt64
}

// MARK: - #23 BufferEncodable / BufferDecodable (hand-written, codegen-faithful)

//  Encode each stored field in declaration order; decode in the same order. Arrays go through the
//  library's `Array` conformance (CollectionHeader + elements). `DeltaStatusLike` rides the
//  `RawRepresentable` conformance (its UInt8 raw value). Int64/Int32/UInt16/UInt8/UInt64/Int
//  already conform. Encode is non-throwing for every field type here, so message-level encode is
//  non-throwing (`SerializationError == Never`); decode is `throws(BufferDecodingError)`.

extension DeltaStatusLike: BufferEncodable, BufferDecodable {}

extension QuoteTableLike: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        self.windowLow.encode(to: &output)
        self.windowHigh.encode(to: &output)
        self.baseTickSize.encode(to: &output)
        self.prices.encode(to: &output)
        self.priceOffsets.encode(to: &output)
    }
}
extension QuoteTableLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let windowLow: Int64 = try .decode(from: &input)
        let windowHigh: Int64 = try .decode(from: &input)
        let baseTickSize: Int64 = try .decode(from: &input)
        let prices: [Int64] = try .decode(from: &input)
        let priceOffsets: [Int32] = try .decode(from: &input)
        return .init(
            windowLow: windowLow, windowHigh: windowHigh, baseTickSize: baseTickSize,
            prices: prices, priceOffsets: priceOffsets
        )
    }
}

extension TransitionIndexLike: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        self.offsets.encode(to: &output)
        self.entries.encode(to: &output)
    }
}
extension TransitionIndexLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let offsets: [Int32] = try .decode(from: &input)
        let entries: [UInt16] = try .decode(from: &input)
        return .init(offsets: offsets, entries: entries)
    }
}

extension QuoteTablesLike: BufferEncodable {
    func encode(to output: inout BufferEncoder) {
        self.baseInstrument.encode(to: &output)
        self.bidTable.encode(to: &output)
        self.askTable.encode(to: &output)
        self.bidTransitionIndex.encode(to: &output)
        self.askTransitionIndex.encode(to: &output)
        self.deltaStatus.encode(to: &output)
        self.windowTicks.encode(to: &output)
        self.windowGeneration.encode(to: &output)
        self.settingsGeneration.encode(to: &output)
    }
}
extension QuoteTablesLike: BufferDecodable {
    static func decode(from input: inout BufferDecoder) throws(BufferDecodingError) -> Self {
        let baseInstrument: UInt64 = try .decode(from: &input)
        let bidTable: QuoteTableLike = try .decode(from: &input)
        let askTable: QuoteTableLike = try .decode(from: &input)
        let bidTransitionIndex: TransitionIndexLike = try .decode(from: &input)
        let askTransitionIndex: TransitionIndexLike = try .decode(from: &input)
        let deltaStatus: [UInt8] = try .decode(from: &input)
        let windowTicks: Int = try .decode(from: &input)
        let windowGeneration: UInt64 = try .decode(from: &input)
        let settingsGeneration: UInt64 = try .decode(from: &input)
        return .init(
            baseInstrument: baseInstrument,
            bidTable: bidTable, askTable: askTable,
            bidTransitionIndex: bidTransitionIndex, askTransitionIndex: askTransitionIndex,
            deltaStatus: deltaStatus,
            windowTicks: windowTicks,
            windowGeneration: windowGeneration, settingsGeneration: settingsGeneration
        )
    }
}

// MARK: - #24 SpanDecodable (mirror of the #23 decode path, over a zero-copy SpanDecoder)

extension DeltaStatusLike: SpanDecodable {}

extension QuoteTableLike: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        let windowLow: Int64 = try .decode(from: &input)
        let windowHigh: Int64 = try .decode(from: &input)
        let baseTickSize: Int64 = try .decode(from: &input)
        let prices: [Int64] = try .decode(from: &input)
        let priceOffsets: [Int32] = try .decode(from: &input)
        return .init(
            windowLow: windowLow, windowHigh: windowHigh, baseTickSize: baseTickSize,
            prices: prices, priceOffsets: priceOffsets
        )
    }
}
extension TransitionIndexLike: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        let offsets: [Int32] = try .decode(from: &input)
        let entries: [UInt16] = try .decode(from: &input)
        return .init(offsets: offsets, entries: entries)
    }
}
extension QuoteTablesLike: SpanDecodable {
    static func decode(from input: inout SpanDecoder) throws(BufferDecodingError) -> Self {
        let baseInstrument: UInt64 = try .decode(from: &input)
        let bidTable: QuoteTableLike = try .decode(from: &input)
        let askTable: QuoteTableLike = try .decode(from: &input)
        let bidTransitionIndex: TransitionIndexLike = try .decode(from: &input)
        let askTransitionIndex: TransitionIndexLike = try .decode(from: &input)
        let deltaStatus: [UInt8] = try .decode(from: &input)
        let windowTicks: Int = try .decode(from: &input)
        let windowGeneration: UInt64 = try .decode(from: &input)
        let settingsGeneration: UInt64 = try .decode(from: &input)
        return .init(
            baseInstrument: baseInstrument,
            bidTable: bidTable, askTable: askTable,
            bidTransitionIndex: bidTransitionIndex, askTransitionIndex: askTransitionIndex,
            deltaStatus: deltaStatus,
            windowTicks: windowTicks,
            windowGeneration: windowGeneration, settingsGeneration: settingsGeneration
        )
    }
}

// MARK: - #24 SpanEncoder caller-loops + encodedSize (there is no SpanEncodable protocol)

//  Each leaf method writes the SAME bytes its `BufferEncodable` counterpart produces. A scalar is
//  `appendLittleEndian`; an array is `append(collectionHeader:)` + a loop of the element leaf
//  method (matching `Collection.encode`'s header + element-in-order layout). The field ORDER here
//  is the SAME declaration order the #23 `encode(to:)` uses, so the bytes match (asserted below).

//  `collectionHeaderSize(_:)` (1 byte if count < 255, else 1 + 8-byte Int) is shared with
//  OrdoDictPayloads.swift; reuse it rather than redeclare.

func encodedSizeQuoteTable(_ t: QuoteTableLike) -> Int {
    var n: Int = 3 * MemoryLayout<Int64>.size                          // windowLow/High/baseTickSize
    n += collectionHeaderSize(t.prices.count) + t.prices.count * MemoryLayout<Int64>.size
    n += collectionHeaderSize(t.priceOffsets.count) + t.priceOffsets.count * MemoryLayout<Int32>.size
    return n
}
func encodedSizeTransitionIndex(_ t: TransitionIndexLike) -> Int {
    var n: Int = collectionHeaderSize(t.offsets.count) + t.offsets.count * MemoryLayout<Int32>.size
    n += collectionHeaderSize(t.entries.count) + t.entries.count * MemoryLayout<UInt16>.size
    return n
}
func encodedSizeQuoteTables(_ t: QuoteTablesLike) -> Int {
    var n: Int = MemoryLayout<UInt64>.size                             // baseInstrument
    n += encodedSizeQuoteTable(t.bidTable) + encodedSizeQuoteTable(t.askTable)
    n += encodedSizeTransitionIndex(t.bidTransitionIndex)
    n += encodedSizeTransitionIndex(t.askTransitionIndex)
    n += collectionHeaderSize(t.deltaStatus.count) + t.deltaStatus.count   // UInt8 = 1 byte each
    n += MemoryLayout<Int>.size                                        // windowTicks
    n += 2 * MemoryLayout<UInt64>.size                                 // window/settingsGeneration
    return n
}

func spanEncodeQuoteTable(_ t: QuoteTableLike, into s: inout SpanEncoder) {
    s.appendLittleEndian(t.windowLow)
    s.appendLittleEndian(t.windowHigh)
    s.appendLittleEndian(t.baseTickSize)
    s.append(collectionHeader: t.prices.count)
    for v: Int64 in t.prices { s.appendLittleEndian(v) }
    s.append(collectionHeader: t.priceOffsets.count)
    for v: Int32 in t.priceOffsets { s.appendLittleEndian(v) }
}
func spanEncodeTransitionIndex(_ t: TransitionIndexLike, into s: inout SpanEncoder) {
    s.append(collectionHeader: t.offsets.count)
    for v: Int32 in t.offsets { s.appendLittleEndian(v) }
    s.append(collectionHeader: t.entries.count)
    for v: UInt16 in t.entries { s.appendLittleEndian(v) }
}
func spanEncodeQuoteTables(_ t: QuoteTablesLike, into s: inout SpanEncoder) {
    s.appendLittleEndian(t.baseInstrument)
    spanEncodeQuoteTable(t.bidTable, into: &s)
    spanEncodeQuoteTable(t.askTable, into: &s)
    spanEncodeTransitionIndex(t.bidTransitionIndex, into: &s)
    spanEncodeTransitionIndex(t.askTransitionIndex, into: &s)
    s.append(collectionHeader: t.deltaStatus.count)
    for v: UInt8 in t.deltaStatus { s.append(v) }
    s.appendLittleEndian(t.windowTicks)
    s.appendLittleEndian(t.windowGeneration)
    s.appendLittleEndian(t.settingsGeneration)
}

// MARK: - Seeded PRNG + fixture (built ONCE, outside any measured region)

/// SplitMix64 — deterministic so the fixture is byte-identical across runs/worktrees and all
/// three serializers measure the SAME bytes.
struct QTSplitMix64 {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        self.state = self.state &+ 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = self.state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum QuoteTableFixtures {
    /// Build a `QuoteTablesLike` with `N` instruments, matching HotPathBenchmark conventions:
    /// windowTicks = 200, per-instrument-per-side rangeCount = (rng % 8) + 3, CSR priceOffsets of
    /// length N+1, transitionsPerTick = N/10 (entries length = windowTicks * N/10 per side,
    /// offsets length = windowTicks + 1), deltaStatus length = N * windowTicks.
    static func make(instrumentCount N: Int) -> QuoteTablesLike {
        var prng: QTSplitMix64 = .init(seed: 0x5175_6F74_6572_0000 &+ UInt64(N))
        let windowTicks: Int = 200
        let transitionsPerTick: Int = max(1, N / 10)

        func makeTable() -> QuoteTableLike {
            var prices: [Int64] = []
            var offsets: [Int32] = []
            offsets.reserveCapacity(N + 1)
            for _ in 0 ..< N {
                offsets.append(Int32(prices.count))
                let rangeCount: Int = Int(prng.next() % 8) + 3   // 3..10, avg ~6.5
                for _ in 0 ..< rangeCount {
                    //  Plausible price as Int64 (FixedPointDecimal-scaled), some "no quote".
                    prices.append(Int64(bitPattern: prng.next() & 0x0000_00FF_FFFF_FFFF))
                }
            }
            offsets.append(Int32(prices.count))
            return .init(
                windowLow: Int64(bitPattern: prng.next()),
                windowHigh: Int64(bitPattern: prng.next()),
                baseTickSize: 1_000,   // e.g. 0.01 scaled
                prices: prices,
                priceOffsets: offsets
            )
        }

        func makeTransitionIndex() -> TransitionIndexLike {
            var offsets: [Int32] = []
            offsets.reserveCapacity(windowTicks + 1)
            var entries: [UInt16] = []
            entries.reserveCapacity(windowTicks * transitionsPerTick)
            var running: Int32 = 0
            for _ in 0 ..< windowTicks {
                offsets.append(running)
                for _ in 0 ..< transitionsPerTick {
                    entries.append(UInt16(prng.next() % UInt64(N)))
                }
                running &+= Int32(transitionsPerTick)
            }
            offsets.append(running)
            return .init(offsets: offsets, entries: entries)
        }

        let bidTable: QuoteTableLike = makeTable()
        let askTable: QuoteTableLike = makeTable()
        let bidTransitionIndex: TransitionIndexLike = makeTransitionIndex()
        let askTransitionIndex: TransitionIndexLike = makeTransitionIndex()

        var deltaStatus: [UInt8] = []
        deltaStatus.reserveCapacity(N * windowTicks)
        for _ in 0 ..< (N * windowTicks) {
            deltaStatus.append(UInt8(prng.next() % 4))   // one of the 4 DeltaStatus cases
        }

        return .init(
            baseInstrument: prng.next(),
            bidTable: bidTable, askTable: askTable,
            bidTransitionIndex: bidTransitionIndex, askTransitionIndex: askTransitionIndex,
            deltaStatus: deltaStatus,
            windowTicks: windowTicks,
            windowGeneration: prng.next(),
            settingsGeneration: prng.next()
        )
    }
}

// MARK: - Wire helpers

/// #23: encode the payload through `BufferEncoder` into an owned [UInt8].
func quoteBuf23Bytes(_ t: QuoteTablesLike) -> [UInt8] {
    var e: BufferEncoder = .init(capacity: encodedSizeQuoteTables(t))
    t.encode(to: &e)
    return e.finalize()
}

/// #24: encode through a `SpanEncoder` caller-loop into a reserved region -> [UInt8].
func quoteSpan24Bytes(_ t: QuoteTablesLike) -> [UInt8] {
    let size: Int = encodedSizeQuoteTables(t)
    let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: size, alignment: 1)
    defer { reserved.deallocate() }
    let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
    var s: SpanEncoder = .init(raw)
    spanEncodeQuoteTables(t, into: &s)
    let written: Int = s.finalize()
    return [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< written]))
}

/// #24: decode a [UInt8] through `SpanDecoder` (zero-copy over a borrowed RawSpan).
func quoteSpan24Decode(_ bytes: [UInt8]) throws -> QuoteTablesLike {
    try bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> QuoteTablesLike in
        var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
        return try QuoteTablesLike.decode(from: &d)
    }
}

// MARK: - Correctness (asserted at fixture-build time, before any benchmark runs)

//  A. JSON   decode(encode(x)) == x
//  B. #23    decode(encode(x)) == x
//  C. #24    SpanDecode(SpanEncode(x)) == x
//  D. #23 bytes == #24 bytes  (the two binary encode paths agree byte-for-byte)
func quoteCorrect(_ t: QuoteTablesLike) -> Bool {
    do {
        // A. JSON round-trip
        let json: Data = try JSONEncoder().encode(t)
        guard try JSONDecoder().decode(QuoteTablesLike.self, from: json) == t else { return false }

        // B. #23 round-trip
        let bytes23: [UInt8] = quoteBuf23Bytes(t)
        var d23: BufferDecoder = .init(bytes23[...])
        guard try QuoteTablesLike.decode(from: &d23) == t else { return false }

        // C. #24 round-trip
        let bytes24: [UInt8] = quoteSpan24Bytes(t)
        guard try quoteSpan24Decode(bytes24) == t else { return false }

        // D. #23 bytes == #24 bytes
        guard bytes23 == bytes24 else { return false }

        return true
    } catch {
        return false
    }
}

// MARK: - Registration

func registerQuoteTableBenchmarks() {
    //  Full metric set so staging/receive-copy allocation + ARC are visible alongside the lead
    //  `instructions` / `mallocCountTotal` counts.
    let metrics: [BenchmarkMetric] =
        [.wallClock, .instructions, .throughput] + BenchmarkMetric.memory + BenchmarkMetric.arc
    func config() -> Benchmark.Configuration { .init(metrics: metrics, timeUnits: .microseconds) }

    for N: Int in [3_000, 5_000] {
        //  Build the fixture ONCE, outside any measured region, and assert all four correctness
        //  properties before a single benchmark runs.
        let payload: QuoteTablesLike = QuoteTableFixtures.make(instrumentCount: N)
        precondition(quoteCorrect(payload), "QuoteTable N=\(N): roundtrip or #23/#24 byte mismatch")

        //  Pre-encode the wire buffers ONCE so the decode benchmarks read a stable byte stream.
        //  These also pin the WIRE BYTE SIZE headline (JSON vs binary).
        let jsonWire: [UInt8] = [UInt8](try! JSONEncoder().encode(payload))
        let wire23: [UInt8] = quoteBuf23Bytes(payload)
        let wire24: [UInt8] = quoteSpan24Bytes(payload)
        let cap: Int = encodedSizeQuoteTables(payload)

        //  Surface the byte sizes in the run log (the headline size gap: JSON renders ints as
        //  ASCII, binary is fixed-width). Captured in the PR table.
        print("[QuoteTable N=\(N)] wire bytes — JSON: \(jsonWire.count), #23 binary: \(wire23.count), #24 binary: \(wire24.count)")

        // ---- Engine -> Quoter quoteTable(_:) (QuoterEndpoints.swift:161) — JSON (TODAY) ----
        Benchmark.init("QuoteTable JSON encode \(N)", configuration: config()) { benchmark in
            let encoder: JSONEncoder = .init()
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try encoder.encode(payload))
            }
        }
        Benchmark.init("QuoteTable JSON decode \(N)", configuration: config()) { benchmark in
            let data: Data = Data(jsonWire)
            let decoder: JSONDecoder = .init()
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try decoder.decode(QuoteTablesLike.self, from: data))
            }
        }

        // ---- #23 DistributedABI ([UInt8] BufferEncoder / ArraySlice BufferDecoder) ----
        Benchmark.init("QuoteTable #23 encode \(N)", configuration: config()) { benchmark in
            //  Reuse the [UInt8] backing across iterations (zero-copy hand-off in/out of the
            //  encoder); the produced [UInt8] IS the send buffer.
            var buffer: [UInt8] = []
            buffer.reserveCapacity(cap)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                buffer.removeAll(keepingCapacity: true)
                var e: BufferEncoder = .init(preallocated: buffer)
                buffer = []
                payload.encode(to: &e)          // throws(Never)
                buffer = e.finalize()
                blackHole(buffer.count)         // model the send copy reading the wire
            }
        }
        Benchmark.init("QuoteTable #23 decode \(N)", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                //  Model the ByteBuffer -> Array receive copy: a FRESH [UInt8] per message.
                let copy: [UInt8] = Array(wire23)
                var d: BufferDecoder = .init(copy[...])
                blackHole(try QuoteTablesLike.decode(from: &d))
            }
        }

        // ---- #24 DistributedABI (zero-copy SpanEncoder / SpanDecoder) ----
        Benchmark.init("QuoteTable #24 encode \(N)", configuration: config()) { benchmark in
            //  Reserve the destination region ONCE outside the loop. Per iteration: the
            //  encodedSize pass (priced IN, since the reserve needs it per message) + direct
            //  writes straight into the region (no staging buffer, no send copy).
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: cap, alignment: 1)
            defer { reserved.deallocate() }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let size: Int = encodedSizeQuoteTables(payload)
                let region: UnsafeMutableRawBufferPointer = .init(rebasing: reserved[0 ..< size])
                let raw: OutputRawSpan = .init(buffer: region, initializedCount: 0)
                var s: SpanEncoder = .init(raw)
                spanEncodeQuoteTables(payload, into: &s)
                blackHole(s.finalize())
            }
        }
        Benchmark.init("QuoteTable #24 decode \(N)", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                wire24.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
                    blackHole(try! QuoteTablesLike.decode(from: &d))
                }
            }
        }
    }
}
