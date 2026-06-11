import Benchmark
import DistributedABI

//  ORDO RUNTIME RPC DICTIONARY PAYLOADS — the distributed-call sites the SDK census missed.
//
//  The data-model census (~/GitHub/package-data-model) found ZERO Dictionary fields, but the
//  RUNTIME itself ships Dictionary-typed RPC payloads on its cache-synchronization hot path
//  (~/GitHub/internal-distributed-system .../Endpoints/LoadBalancer/Cache+Synchronization.swift).
//  Those are real distributed-call arguments serialized on EVERY ServerEndpoint.sendBuffers().
//  This file measures the three of them against BOTH serialization systems:
//
//    #23 — the [UInt8]-backed `BufferEncoder` + `ArraySlice` `BufferDecoder` path. Encode stages
//          into an owned [UInt8] (the send copy); decode reads a fresh [UInt8] (the ByteBuffer ->
//          Array receive copy production pays).
//    #24 — the zero-copy `SpanEncoder` (writes straight into a reserved region, no staging, no
//          send copy) + `SpanDecoder` (decodes from borrowed memory, no receive copy).
//
//  Both systems serialize the SAME wire format, so the encode paths must produce byte-identical
//  output — asserted at fixture-build time. Fixtures are built ONCE outside the measured region
//  with a seeded SplitMix64 PRNG so they are reproducible and identical across worktrees, and the
//  measured region only does the encode (into a reused/reserved buffer) or decode (from a
//  pre-encoded wire buffer).
//
//  There is NO `SpanEncodable` protocol in #24 (by design — see SpanEncoder's doc comment), so the
//  #24 encode side writes each dictionary through a CALLER LOOP over the library's concrete
//  `SpanEncoder` leaf methods (`append(collectionHeader:)`, `appendLittleEndian`, `append(_:String)`,
//  the optional discriminant). The byte layout still lives in the library leaf methods; this file
//  only owns the field ORDER (which it takes straight from `Dictionary.encode`'s `for (k, v) in self`).

// MARK: - Seeded PRNG (reproducible fixtures, built once)

/// SplitMix64 — a tiny, fast, fully-deterministic PRNG so the three fixtures are byte-identical
/// across runs and across worktrees (production / #23 / #24 are compared on the SAME data).
struct SplitMix64: RandomNumberGenerator {
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

// MARK: - Fixtures (built ONCE, outside any measured region)

//  (1) handleObjects — [Int: [String: Int]]
//      HOT — cache-sync object data stream.
//      Real site: ~/GitHub/internal-distributed-system .../Endpoints/LoadBalancer/Cache+Synchronization.swift:89
//      backed by Buffers.lastOffsets, flushed on every ServerEndpoint.sendBuffers().
//      64 outer entries (keys 0..63), each inner [String: Int] of 16 entries; inner keys are
//      12-char "datacenter-NN" strings, inner values random non-negative Int (~1024 leaf pairs).
//
//  (2) handleBarrierOffsets — [String: [Int32: Int64]]
//      WARM — per cache barrier.
//      Real site: Cache+Synchronization.swift:93, type
//      LastOffsets = [Datacenter.Name: [Storage.Partition: Storage.Offset]].
//      8 outer entries (keys "datacenter-N"), each inner [Int32: Int64] of 64 entries
//      (partition id -> random offset).
//
//  (3) objectSetCacheSynchronizationRequest — modeled as [UInt64: UInt64?]
//      WARM — per ObjectSet resync.
//      Real site: Cache+Synchronization.swift:14, real type [ObjectID: CacheSynchronizationSource?];
//      we model ObjectID as UInt64 and the optional source as UInt64? (NOTED as a proxy).
//      1000 entries, keys random UInt64, values .some(random UInt64) for even-index entries and
//      nil for odd.

enum OrdoDictFixtures {
    /// (1) handleObjects — [Int: [String: Int]], 64 x 16.
    static func handleObjects() -> [Int: [String: Int]] {
        var prng: SplitMix64 = .init(seed: 0x4F52_444F_0000_0001)
        var outer: [Int: [String: Int]] = .init(minimumCapacity: 24)
        for o in 0 ..< 24 {                                     // 24 partitions
            var inner: [String: Int] = .init(minimumCapacity: 4)
            for k in 0 ..< 4 {                                  // 4 datacenters
                //  12-char datacenter-ish key "datacenter-NN" (NN = 00..15).
                let key: String = "datacenter-\(String(format2: k))"
                inner[key] = Int(prng.next() & 0x7FFF_FFFF_FFFF_FFFF)  // non-negative
            }
            outer[o] = inner
        }
        return outer
    }

    /// (2) handleBarrierOffsets — [String: [Int32: Int64]], 8 x 64.
    static func handleBarrierOffsets() -> [String: [Int32: Int64]] {
        var prng: SplitMix64 = .init(seed: 0x4F52_444F_0000_0002)
        var outer: [String: [Int32: Int64]] = .init(minimumCapacity: 4)
        for d in 0 ..< 4 {                                      // 4 datacenters
            let key: String = "datacenter-\(d)"
            var inner: [Int32: Int64] = .init(minimumCapacity: 24)
            for p in 0 ..< 24 {                                 // 24 partitions
                inner[Int32(p)] = Int64(bitPattern: prng.next())  // random offset
            }
            outer[key] = inner
        }
        return outer
    }

    /// (3) objectSetCacheSynchronizationRequest — [UInt64: UInt64?], 1000 entries.
    static func objectSet(_ n: Int) -> [UInt64: UInt64?] {
        var prng: SplitMix64 = .init(seed: 0x4F52_444F_0000_0003)
        var dict: [UInt64: UInt64?] = .init(minimumCapacity: n)
        for i in 0 ..< n {
            let key: UInt64 = prng.next()
            //  even index -> .some(random), odd index -> nil.
            let value: UInt64? = (i & 1 == 0) ? prng.next() : nil
            dict[key] = .some(value)  // store the OPTIONAL value (so nil is a present nil)
        }
        return dict
    }
}

/// Zero-pad a 0..99 integer to two digits without `String(format:)` (keeps the key exactly
/// 12 chars: "datacenter-NN").
extension String {
    fileprivate init(format2 n: Int) {
        if n < 10 { self = "0\(n)" } else { self = "\(n)" }
    }
}

// MARK: - encodedSize (the cheap size pass #24's reserve path needs, per message)

//  Closed-form wire sizes, recursive for nested dictionaries. Mirrors the library leaf-method
//  byte layout exactly:
//    * collectionHeader = 1 byte if count < 255 else 9 (0xFF + 8-byte Int);
//    * fixed-width integer = MemoryLayout<T>.size;
//    * String compact (<= 256 UTF-8 bytes, no NUL) = 1 + utf8.count + 1; long = 6 + utf8.count;
//      empty = 1;
//    * optional = 1 + (some ? wrapped size : 0).

@inline(__always) func collectionHeaderSize(_ count: Int) -> Int {
    count < 255 ? 1 : 1 + MemoryLayout<Int>.size
}

@inline(__always) func stringEncodedSize(_ s: String) -> Int {
    let count: Int = s.utf8.count
    if count == 0 { return 1 }
    if count <= 256 && !s.utf8.contains(0) { return 2 + count }  // 1 format + bytes + 1 NUL
    return 6 + count                                             // 1 format + 4 low + 1 high + bytes
}

func encodedSizeHandleObjects(_ dict: [Int: [String: Int]]) -> Int {
    var n: Int = collectionHeaderSize(dict.count)
    for (_, inner) in dict {
        n += MemoryLayout<Int>.size               // outer Int key
        n += collectionHeaderSize(inner.count)    // inner header
        for (k, _) in inner {
            n += stringEncodedSize(k)             // inner String key
            n += MemoryLayout<Int>.size           // inner Int value
        }
    }
    return n
}

func encodedSizeHandleBarrierOffsets(_ dict: [String: [Int32: Int64]]) -> Int {
    var n: Int = collectionHeaderSize(dict.count)
    for (k, inner) in dict {
        n += stringEncodedSize(k)                 // outer String key
        n += collectionHeaderSize(inner.count)    // inner header
        for (_, _) in inner {
            n += MemoryLayout<Int32>.size         // inner Int32 key
            n += MemoryLayout<Int64>.size         // inner Int64 value
        }
    }
    return n
}

func encodedSizeObjectSet(_ dict: [UInt64: UInt64?]) -> Int {
    var n: Int = collectionHeaderSize(dict.count)
    for (_, value) in dict {
        n += MemoryLayout<UInt64>.size            // UInt64 key
        n += 1                                     // optional discriminant
        if value != nil { n += MemoryLayout<UInt64>.size }
    }
    return n
}

// MARK: - #24 SpanEncoder caller-loops (field ORDER from Dictionary.encode; bytes from library)

//  Each loop iterates the SAME dictionary value `Dictionary.encode` iterates (`for (k, v) in self`),
//  so the element order — and therefore the bytes — match the #23 path exactly. Verified by
//  byte-equality at fixture-build time.

func spanEncodeHandleObjects(_ dict: [Int: [String: Int]], into s: inout SpanEncoder) {
    s.append(collectionHeader: dict.count)
    for (key, inner) in dict {
        s.appendLittleEndian(key)
        s.append(collectionHeader: inner.count)
        for (ik, iv) in inner {
            s.append(ik)
            s.appendLittleEndian(iv)
        }
    }
}

func spanEncodeHandleBarrierOffsets(_ dict: [String: [Int32: Int64]], into s: inout SpanEncoder) {
    s.append(collectionHeader: dict.count)
    for (key, inner) in dict {
        s.append(key)
        s.append(collectionHeader: inner.count)
        for (ik, iv) in inner {
            s.appendLittleEndian(ik)
            s.appendLittleEndian(iv)
        }
    }
}

func spanEncodeObjectSet(_ dict: [UInt64: UInt64?], into s: inout SpanEncoder) {
    s.append(collectionHeader: dict.count)
    for (key, value) in dict {
        s.appendLittleEndian(key)
        if let value {
            s.append(UInt8(1))                  // Optional.BinaryFormat.some
            s.appendLittleEndian(value)
        } else {
            s.append(UInt8(0))                  // Optional.BinaryFormat.none
        }
    }
}

// MARK: - Correctness (asserted at fixture-build time)

//  For each payload, prove:
//    A. #23 decode(#23 encode(x)) == x
//    B. #24 SpanDecoder-decode(#24 SpanEncoder-encode(x)) == x
//    C. #24 bytes == #23 bytes  (the SpanEncoder caller-loop produces the SAME wire format as
//       Dictionary.encode — this proves the two encode paths agree).

/// Encode a dict through #23 (`Dictionary.encode` into a `BufferEncoder`) -> [UInt8].
func buf23Bytes<K: BufferEncodable, V: BufferEncodable>(
    _ dict: [K: V]
) -> [UInt8] where V.SerializationError == Never, K.SerializationError == Never {
    var e: BufferEncoder = .init(capacity: 64)
    dict.encode(to: &e)
    return e.finalize()
}

/// Encode a dict through #24 (a SpanEncoder caller-loop over a reserved region) -> [UInt8].
func span24Bytes(_ size: Int, _ write: (inout SpanEncoder) -> Void) -> [UInt8] {
    let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: size, alignment: 1)
    defer { reserved.deallocate() }
    let raw: OutputRawSpan = .init(buffer: reserved, initializedCount: 0)
    var s: SpanEncoder = .init(raw)
    write(&s)
    let written: Int = s.finalize()
    return [UInt8](UnsafeRawBufferPointer(rebasing: reserved[0 ..< written]))
}

/// Decode a [UInt8] through #24 (`SpanDecoder`) back to a dict.
func span24Decode<T: SpanDecodable>(_ bytes: [UInt8], as _: T.Type) throws -> T
where T.DeserializationError == BufferDecodingError {
    try bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> T in
        var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
        return try T.decode(from: &d)
    }
}

func ordoDictCorrect() -> Bool {
    do {
        //  (1) handleObjects
        let ho: [Int: [String: Int]] = OrdoDictFixtures.handleObjects()
        let hoBytes23: [UInt8] = buf23Bytes(ho)
        let hoBytes24: [UInt8] = span24Bytes(encodedSizeHandleObjects(ho)) { spanEncodeHandleObjects(ho, into: &$0) }
        guard hoBytes24 == hoBytes23 else { return false }
        var hoD: BufferDecoder = .init(hoBytes23[...])
        guard try [Int: [String: Int]].decode(from: &hoD) == ho else { return false }
        guard try span24Decode(hoBytes24, as: [Int: [String: Int]].self) == ho else { return false }

        //  (2) handleBarrierOffsets
        let bo: [String: [Int32: Int64]] = OrdoDictFixtures.handleBarrierOffsets()
        let boBytes23: [UInt8] = buf23Bytes(bo)
        let boBytes24: [UInt8] = span24Bytes(encodedSizeHandleBarrierOffsets(bo)) { spanEncodeHandleBarrierOffsets(bo, into: &$0) }
        guard boBytes24 == boBytes23 else { return false }
        var boD: BufferDecoder = .init(boBytes23[...])
        guard try [String: [Int32: Int64]].decode(from: &boD) == bo else { return false }
        guard try span24Decode(boBytes24, as: [String: [Int32: Int64]].self) == bo else { return false }

        //  (3) objectSet (representative size for the correctness check)
        let os: [UInt64: UInt64?] = OrdoDictFixtures.objectSet(1_000)
        let osBytes23: [UInt8] = buf23Bytes(os)
        let osBytes24: [UInt8] = span24Bytes(encodedSizeObjectSet(os)) { spanEncodeObjectSet(os, into: &$0) }
        guard osBytes24 == osBytes23 else { return false }
        var osD: BufferDecoder = .init(osBytes23[...])
        guard try [UInt64: UInt64?].decode(from: &osD) == os else { return false }
        guard try span24Decode(osBytes24, as: [UInt64: UInt64?].self) == os else { return false }

        return true
    } catch {
        return false
    }
}

// MARK: - Registration

func registerOrdoDictBenchmarks() {
    //  Full metric set so the staging/receive-copy allocation + ARC are visible alongside the
    //  lead `instructions` / `mallocCountTotal` counts.
    let metrics: [BenchmarkMetric] =
        [.wallClock, .instructions, .throughput] + BenchmarkMetric.memory + BenchmarkMetric.arc
    func config() -> Benchmark.Configuration { .init(metrics: metrics, timeUnits: .microseconds) }

    //  Build ALL fixtures ONCE, outside any measured region, and assert all three correctness
    //  properties (A/B/C) before a single benchmark runs.
    precondition(ordoDictCorrect(), "OrdoDict: #23/#24 roundtrip or byte-equality mismatch")

    let handleObjects: [Int: [String: Int]] = OrdoDictFixtures.handleObjects()
    let handleBarrierOffsets: [String: [Int32: Int64]] = OrdoDictFixtures.handleBarrierOffsets()

    // ============================================================ handleObjects (HOT)
    do {
        let dict: [Int: [String: Int]] = handleObjects
        let cap: Int = encodedSizeHandleObjects(dict)
        //  #24 decode reads from a wire buffer pre-encoded ONCE.
        let wire24: [UInt8] = span24Bytes(cap) { spanEncodeHandleObjects(dict, into: &$0) }
        //  #23 decode reads from a wire buffer pre-encoded ONCE.
        let wire23: [UInt8] = buf23Bytes(dict)

        Benchmark.init("#23 handleObjects encode", configuration: config()) { benchmark in
            //  Reuse the [UInt8] backing across iterations (zero-copy hand-off in/out of the
            //  encoder), encode the dict, then model the send copy by reading the produced [UInt8].
            var buffer: [UInt8] = []
            buffer.reserveCapacity(cap)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                buffer.removeAll(keepingCapacity: true)
                var e: BufferEncoder = .init(preallocated: buffer)
                buffer = []
                dict.encode(to: &e)          // throws(Never)
                buffer = e.finalize()        // the produced wire bytes (the [UInt8] IS the wire)
                blackHole(buffer.count)      // model the send copy reading the wire
            }
        }
        Benchmark.init("#23 handleObjects decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                //  Model the ByteBuffer -> Array receive copy: a FRESH [UInt8] per message.
                let copy: [UInt8] = Array(wire23)
                var d: BufferDecoder = .init(copy[...])
                blackHole(try [Int: [String: Int]].decode(from: &d))
            }
        }
        Benchmark.init("#24 handleObjects encode", configuration: config()) { benchmark in
            //  Reserve the destination region ONCE outside the loop. Per iteration: the
            //  encodedSize pass (priced IN, since reserve needs it per message) + direct writes.
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: cap, alignment: 1)
            defer { reserved.deallocate() }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let size: Int = encodedSizeHandleObjects(dict)
                let region: UnsafeMutableRawBufferPointer = .init(rebasing: reserved[0 ..< size])
                let raw: OutputRawSpan = .init(buffer: region, initializedCount: 0)
                var s: SpanEncoder = .init(raw)
                spanEncodeHandleObjects(dict, into: &s)
                blackHole(s.finalize())
            }
        }
        Benchmark.init("#24 handleObjects decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                wire24.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
                    blackHole(try! [Int: [String: Int]].decode(from: &d))
                }
            }
        }
    }

    // ============================================================ handleBarrierOffsets (WARM)
    do {
        let dict: [String: [Int32: Int64]] = handleBarrierOffsets
        let cap: Int = encodedSizeHandleBarrierOffsets(dict)
        let wire24: [UInt8] = span24Bytes(cap) { spanEncodeHandleBarrierOffsets(dict, into: &$0) }
        let wire23: [UInt8] = buf23Bytes(dict)

        Benchmark.init("#23 handleBarrierOffsets encode", configuration: config()) { benchmark in
            var buffer: [UInt8] = []
            buffer.reserveCapacity(cap)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                buffer.removeAll(keepingCapacity: true)
                var e: BufferEncoder = .init(preallocated: buffer)
                buffer = []
                dict.encode(to: &e)
                buffer = e.finalize()
                blackHole(buffer.count)
            }
        }
        Benchmark.init("#23 handleBarrierOffsets decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let copy: [UInt8] = Array(wire23)
                var d: BufferDecoder = .init(copy[...])
                blackHole(try [String: [Int32: Int64]].decode(from: &d))
            }
        }
        Benchmark.init("#24 handleBarrierOffsets encode", configuration: config()) { benchmark in
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: cap, alignment: 1)
            defer { reserved.deallocate() }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let size: Int = encodedSizeHandleBarrierOffsets(dict)
                let region: UnsafeMutableRawBufferPointer = .init(rebasing: reserved[0 ..< size])
                let raw: OutputRawSpan = .init(buffer: region, initializedCount: 0)
                var s: SpanEncoder = .init(raw)
                spanEncodeHandleBarrierOffsets(dict, into: &s)
                blackHole(s.finalize())
            }
        }
        Benchmark.init("#24 handleBarrierOffsets decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                wire24.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
                    blackHole(try! [String: [Int32: Int64]].decode(from: &d))
                }
            }
        }
    }

    // ============================================================ objectSet (WARM) — size sweep
    //  objectSet is sized to the object-set count (deployment-dependent), so sweep 1k/10k/100k.
    for n in [1_000, 10_000, 100_000] {
        let dict: [UInt64: UInt64?] = OrdoDictFixtures.objectSet(n)
        let cap: Int = encodedSizeObjectSet(dict)
        let wire24: [UInt8] = span24Bytes(cap) { spanEncodeObjectSet(dict, into: &$0) }
        let wire23: [UInt8] = buf23Bytes(dict)

        Benchmark.init("#23 objectSet \(n) encode", configuration: config()) { benchmark in
            var buffer: [UInt8] = []
            buffer.reserveCapacity(cap)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                buffer.removeAll(keepingCapacity: true)
                var e: BufferEncoder = .init(preallocated: buffer)
                buffer = []
                dict.encode(to: &e)
                buffer = e.finalize()
                blackHole(buffer.count)
            }
        }
        Benchmark.init("#23 objectSet \(n) decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let copy: [UInt8] = Array(wire23)
                var d: BufferDecoder = .init(copy[...])
                blackHole(try [UInt64: UInt64?].decode(from: &d))
            }
        }
        Benchmark.init("#24 objectSet \(n) encode", configuration: config()) { benchmark in
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: cap, alignment: 1)
            defer { reserved.deallocate() }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let size: Int = encodedSizeObjectSet(dict)
                let region: UnsafeMutableRawBufferPointer = .init(rebasing: reserved[0 ..< size])
                let raw: OutputRawSpan = .init(buffer: region, initializedCount: 0)
                var s: SpanEncoder = .init(raw)
                spanEncodeObjectSet(dict, into: &s)
                blackHole(s.finalize())
            }
        }
        Benchmark.init("#24 objectSet \(n) decode", configuration: config()) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                wire24.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    var d: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
                    blackHole(try! [UInt64: UInt64?].decode(from: &d))
                }
            }
        }
    }
}
