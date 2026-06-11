import Benchmark
import DistributedABI
import Foundation

//  "Current production" dictionary serialization benchmarks for three real ordo
//  runtime RPC payloads that the SDK census missed. These exercise the OLD
//  production path: `Dictionary: Transferable` via `withUnsafeBytesSerialization`
//  (encode, ULEB128-length-prefixed key/value pairs into a power-of-2-growing
//  buffer; recursive for nested dicts) and `init(fromSerializedBuffer:)` (decode).
//
//  Each payload is mapped below to the exact ordo runtime distributed-call site
//  it stands in for, with its HOT/WARM classification. The same deterministic
//  fixtures (seeded SplitMix64) are used in both worktrees so production / #23 /
//  #24 are compared on byte-identical data.

//  MARK: - Seeded PRNG (reproducible fixtures)
//
//  SplitMix64 seeded with a constant so the fixtures are byte-for-byte identical
//  on every run and across worktrees. Built ONCE outside the measured region.

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

//  MARK: - Payload (1): handleObjects  —  [Int: [String: Int]]  —  HOT
//
//  Real site: ~/ordo .../Endpoints/LoadBalancer/Cache+Synchronization.swift:89
//  (cache-sync object data stream, backed by Buffers.lastOffsets, flushed on
//  every ServerEndpoint.sendBuffers()).
//  Fixture: 64 outer entries (keys 0..63), each inner [String: Int] of 16 entries;
//  inner keys are 12-char datacenter-ish strings ("datacenter-NN"), inner values
//  are random non-negative Int. ~1024 leaf pairs.

func makeHandleObjects() -> [Int: [String: Int]] {
    var rng = SplitMix64(seed: 0x4F62_6A65_6374_0001)  // "Object" + tag
    var outer: [Int: [String: Int]] = [:]
    outer.reserveCapacity(64)
    for k in 0 ..< 64 {
        var inner: [String: Int] = [:]
        inner.reserveCapacity(16)
        for j in 0 ..< 16 {
            let key = "datacenter-\(String(format: "%02d", j))"  // 12-char "datacenter-NN"
            inner[key] = Int(rng.next() >> 1)                    // non-negative Int
        }
        outer[k] = inner
    }
    return outer
}

//  MARK: - Payload (2): handleBarrierOffsets  —  [String: [Int32: Int64]]  —  WARM
//
//  Real site: Cache+Synchronization.swift:93
//  type LastOffsets = [Datacenter.Name: [Storage.Partition: Storage.Offset]]
//  (per cache barrier).
//  Fixture: 8 outer entries (keys "datacenter-N"), each inner [Int32: Int64] of
//  64 entries (partition id -> random offset).

func makeHandleBarrierOffsets() -> [String: [Int32: Int64]] {
    var rng = SplitMix64(seed: 0x4261_7272_6965_7202)  // "Barrier" + tag
    var outer: [String: [Int32: Int64]] = [:]
    outer.reserveCapacity(8)
    for d in 0 ..< 8 {
        var inner: [Int32: Int64] = [:]
        inner.reserveCapacity(64)
        for p in 0 ..< 64 {
            inner[Int32(p)] = Int64(bitPattern: rng.next())  // random offset
        }
        outer["datacenter-\(d)"] = inner
    }
    return outer
}

//  MARK: - Payload (3): objectSetCacheSynchronizationRequest  —  [UInt64: UInt64?]  —  WARM
//
//  Real site: Cache+Synchronization.swift:14
//  real type [ObjectID: CacheSynchronizationSource?] (per ObjectSet resync). We
//  model ObjectID as UInt64 and the optional source as UInt64? — NOTED as a proxy.
//  Fixture: 1000 entries, keys random UInt64, values .some(random UInt64) for
//  even-index entries and nil for odd.

func makeObjectSet() -> [UInt64: UInt64?] {
    var rng = SplitMix64(seed: 0x4F62_6A53_6574_0003)  // "ObjSet" + tag
    var dict: [UInt64: UInt64?] = [:]
    dict.reserveCapacity(1000)
    var i = 0
    while dict.count < 1000 {
        let key = rng.next()
        let value: UInt64? = (i & 1 == 0) ? .some(rng.next()) : nil
        if dict.index(forKey: key) == nil {
            dict[key] = value
            i += 1
        }
    }
    return dict
}

//  MARK: - Round-trip helpers (production OLD Transferable path)

@inline(never)
func encodeProd<K: Serializable, V: Serializable>(
    _ dict: [K: V], into wire: inout [UInt8]
) {
    dict.withUnsafeBytesSerialization { (bytes: UnsafeRawBufferPointer) in
        wire.removeAll(keepingCapacity: true)
        wire.append(contentsOf: bytes)
    }
}

@inline(never)
func decodeProd<K: Deserializable & Hashable, V: Deserializable>(
    _ wire: [UInt8], as: [K: V].Type = [K: V].self
) throws -> [K: V] {
    try wire.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        try [K: V](fromSerializedBuffer: raw)
    }
}

func preEncode<K: Serializable, V: Serializable>(_ dict: [K: V]) -> [UInt8] {
    var wire: [UInt8] = []
    encodeProd(dict, into: &wire)
    return wire
}

//  MARK: - Registration

func registerOrdoDictPayloads() {
    let metrics: [BenchmarkMetric] =
        [.wallClock, .instructions, .throughput] + BenchmarkMetric.memory + BenchmarkMetric.arc

    //  Build fixtures ONCE outside the measured region, and assert round-trip
    //  correctness at fixture-build time: decode(encode(x)) == x.

    //  (1) handleObjects — [Int: [String: Int]] — HOT
    //      Cache+Synchronization.swift:89 (ServerEndpoint.sendBuffers()).
    let handleObjects = makeHandleObjects()
    let handleObjectsWire = preEncode(handleObjects)
    precondition(
        (try? decodeProd(handleObjectsWire, as: [Int: [String: Int]].self)) == handleObjects,
        "handleObjects round-trip mismatch"
    )

    //  (2) handleBarrierOffsets — [String: [Int32: Int64]] — WARM
    //      Cache+Synchronization.swift:93 (LastOffsets per cache barrier).
    let handleBarrierOffsets = makeHandleBarrierOffsets()
    let handleBarrierOffsetsWire = preEncode(handleBarrierOffsets)
    precondition(
        (try? decodeProd(handleBarrierOffsetsWire, as: [String: [Int32: Int64]].self)) == handleBarrierOffsets,
        "handleBarrierOffsets round-trip mismatch"
    )

    //  (3) objectSet — [UInt64: UInt64?] — WARM
    //      Cache+Synchronization.swift:14 ([ObjectID: CacheSynchronizationSource?]
    //      proxy; per ObjectSet resync).
    let objectSet = makeObjectSet()
    let objectSetWire = preEncode(objectSet)
    precondition(
        (try? decodeProd(objectSetWire, as: [UInt64: UInt64?].self)) == objectSet,
        "objectSet round-trip mismatch"
    )

    //  ENCODE benchmarks: produce wire bytes into a reused [UInt8] (the send
    //  buffer build). blackHole(wire.count).

    //  Cache+Synchronization.swift:89 — HOT
    Benchmark.init(
        "ProdDict handleObjects encode",
        configuration: .init(metrics: metrics, timeUnits: .microseconds)
    ) { benchmark in
        var wire: [UInt8] = []
        wire.reserveCapacity(handleObjectsWire.count)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            encodeProd(handleObjects, into: &wire)
            blackHole(wire.count)
        }
    }

    //  Cache+Synchronization.swift:93 — WARM
    Benchmark.init(
        "ProdDict handleBarrierOffsets encode",
        configuration: .init(metrics: metrics, timeUnits: .microseconds)
    ) { benchmark in
        var wire: [UInt8] = []
        wire.reserveCapacity(handleBarrierOffsetsWire.count)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            encodeProd(handleBarrierOffsets, into: &wire)
            blackHole(wire.count)
        }
    }

    //  Cache+Synchronization.swift:14 — WARM
    Benchmark.init(
        "ProdDict objectSet encode",
        configuration: .init(metrics: metrics, timeUnits: .microseconds)
    ) { benchmark in
        var wire: [UInt8] = []
        wire.reserveCapacity(objectSetWire.count)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            encodeProd(objectSet, into: &wire)
            blackHole(wire.count)
        }
    }

    //  DECODE benchmarks: from a pre-encoded wire buffer built once outside the
    //  measured region; decode via T(fromSerializedBuffer:). blackHole the count.

    //  Cache+Synchronization.swift:89 — HOT
    Benchmark.init(
        "ProdDict handleObjects decode",
        configuration: .init(metrics: metrics, timeUnits: .microseconds)
    ) { benchmark in
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let decoded = try decodeProd(handleObjectsWire, as: [Int: [String: Int]].self)
            blackHole(decoded.count)
        }
    }

    //  Cache+Synchronization.swift:93 — WARM
    Benchmark.init(
        "ProdDict handleBarrierOffsets decode",
        configuration: .init(metrics: metrics, timeUnits: .microseconds)
    ) { benchmark in
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let decoded = try decodeProd(handleBarrierOffsetsWire, as: [String: [Int32: Int64]].self)
            blackHole(decoded.count)
        }
    }

    //  Cache+Synchronization.swift:14 — WARM
    Benchmark.init(
        "ProdDict objectSet decode",
        configuration: .init(metrics: metrics, timeUnits: .microseconds)
    ) { benchmark in
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let decoded = try decodeProd(objectSetWire, as: [UInt64: UInt64?].self)
            blackHole(decoded.count)
        }
    }
}
