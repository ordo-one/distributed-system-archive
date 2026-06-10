import Benchmark
import DistributedABI

//  Zero-copy decode pricing for SpanDecoder (ser-0xff / blindspotbounty review asks).
//
//  This benchmark stacks on #23, which made `BufferEncoder` `[UInt8]`-backed. It does
//  NOT change the decoder: `BufferDecoder` is — by design — a non-owning view over an
//  `ArraySlice<UInt8>`, because a receiver slices the bytes it already has. So the
//  fair, post-#23 decode baseline is exactly variant (a): copy the received bytes into
//  a `[UInt8]` (the ByteBuffer/mmap -> Array receive copy production pays) and decode
//  with the `ArraySlice`-backed `BufferDecoder`. SpanDecoder's whole point is to remove
//  that copy by decoding directly from borrowed memory.
//
//  Three variants decode the SAME pre-encoded wire buffer, swept over a size range so
//  the receive-copy cost shows as a slope, not just an offset. The wire buffer is
//  encoded ONCE before startMeasurement and reused across iterations; only the decode
//  (and, for variant a, the receive copy) is inside the measured region.
//
//  (a) DecodeArrayCopy    — [UInt8] receive copy + the current ArraySlice BufferDecoder.
//                           The post-#23 production decode path.
//  (b) DecodeSpanZeroCopy — RawSpan over the received bytes, no Array copy.
//  (c) DecodeRawFloor     — hand-rolled loadUnaligned per field, the unsafe floor.

/// A representative distributed-system message: a handful of fixed-width fields, two
/// optionals, and a short identifier string — the shape a zero-copy entry point would
/// receive off the wire. Decodes against the SAME wire format through both the
/// production `BufferDecoder` (ArraySlice) path and the `SpanDecoder` (RawSpan) path,
/// so the two are compared byte-for-byte.
struct SpanBenchMessage {
    var a: UInt64
    var b: UInt64
    var c: UInt64
    var d: UInt64
    var e: UInt64
    var f: UInt64
    var g: UInt64?
    var h: UInt64?
    var name: String

    /// Deterministic fixture so every variant decodes identical bytes.
    static func fixture(_ i: Int) -> SpanBenchMessage {
        .init(
            a: UInt64(i) &* 0x9E37_79B9_7F4A_7C15,
            b: UInt64(i) &+ 1,
            c: UInt64(i) &* 131,
            d: 0xDEAD_BEEF_0000_0000 | UInt64(i & 0xFFFF),
            e: UInt64(truncatingIfNeeded: i &* i),
            f: UInt64(i) << 7,
            g: i & 1 == 0 ? UInt64(i) &* 7 : nil,
            h: i & 3 == 0 ? nil : UInt64(i),
            name: "msg-\(i & 0x3FF)"
        )
    }

    func encode(to output: inout BufferEncoder) {
        self.a.encode(to: &output)
        self.b.encode(to: &output)
        self.c.encode(to: &output)
        self.d.encode(to: &output)
        self.e.encode(to: &output)
        self.f.encode(to: &output)
        self.g.encode(to: &output)
        self.h.encode(to: &output)
        self.name.encode(to: &output)
    }

    /// Decode through the production ArraySlice path.
    static func decode(from input: inout BufferDecoder) throws -> SpanBenchMessage {
        .init(
            a: try .decode(from: &input),
            b: try .decode(from: &input),
            c: try .decode(from: &input),
            d: try .decode(from: &input),
            e: try .decode(from: &input),
            f: try .decode(from: &input),
            g: try .decode(from: &input),
            h: try .decode(from: &input),
            name: try .decode(from: &input)
        )
    }

    /// Decode through the zero-copy RawSpan path.
    static func decode(from input: inout SpanDecoder) throws -> SpanBenchMessage {
        .init(
            a: try .decode(from: &input),
            b: try .decode(from: &input),
            c: try .decode(from: &input),
            d: try .decode(from: &input),
            e: try .decode(from: &input),
            f: try .decode(from: &input),
            g: try .decode(from: &input),
            h: try .decode(from: &input),
            name: try .decode(from: &input)
        )
    }
}

/// Encode `count` messages into one contiguous wire buffer (the shape a receiver gets a
/// batched message in). Built ONCE, outside any measured region.
enum SpanWire {
    static func encodeBatch(count: Int) -> [UInt8] {
        var encoder: BufferEncoder = .init(capacity: count * 80)
        for i in 0 ..< count {
            SpanBenchMessage.fixture(i).encode(to: &encoder)
        }
        return [UInt8](encoder.output)
    }
}

//  MARK: - Variant (a): [UInt8] receive copy + current ArraySlice decoder (post-#23 baseline).

@inline(never) func decodeArrayCopy(_ received: [UInt8], count: Int) throws -> [SpanBenchMessage] {
    //  Production receives into a NIO ByteBuffer / LMDB mmap and copies into an Array
    //  before it can construct a BufferDecoder. Model that copy here.
    let copy: [UInt8] = [UInt8](received)
    var decoder: BufferDecoder = .init(copy[...])
    var output: [SpanBenchMessage] = []
    output.reserveCapacity(count)
    for _ in 0 ..< count {
        output.append(try SpanBenchMessage.decode(from: &decoder))
    }
    return output
}

//  MARK: - Variant (b): zero-copy RawSpan decoder, no Array copy.

@inline(never) func decodeSpanZeroCopy(_ received: [UInt8], count: Int) throws -> [SpanBenchMessage] {
    try received.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [SpanBenchMessage] in
        var decoder: SpanDecoder = .init(RawSpan(_unsafeBytes: raw))
        var output: [SpanBenchMessage] = []
        output.reserveCapacity(count)
        for _ in 0 ..< count {
            output.append(try SpanBenchMessage.decode(from: &decoder))
        }
        return output
    }
}

//  MARK: - Variant (c): hand-rolled unsafe floor (loadUnaligned per field).

@inline(never) func decodeRawFloor(_ received: [UInt8], count: Int) -> [SpanBenchMessage] {
    received.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [SpanBenchMessage] in
        var i: Int = 0
        @inline(__always) func u64() -> UInt64 {
            let v = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i, as: UInt64.self))
            i += 8
            return v
        }
        @inline(__always) func optU64() -> UInt64? {
            let tag = raw.loadUnaligned(fromByteOffset: i, as: UInt8.self); i += 1
            if tag == 0 { return nil }
            return u64()
        }
        @inline(__always) func compactString() -> String {
            let format = raw.loadUnaligned(fromByteOffset: i, as: UInt8.self); i += 1
            if format == 2 { return "" }
            let start = i
            while raw.loadUnaligned(fromByteOffset: i, as: UInt8.self) != 0 { i += 1 }
            let s = String(
                decoding: UnsafeRawBufferPointer(rebasing: raw[start ..< i]),
                as: Unicode.UTF8.self
            )
            i += 1
            return s
        }
        var output: [SpanBenchMessage] = []
        output.reserveCapacity(count)
        for _ in 0 ..< count {
            output.append(SpanBenchMessage(
                a: u64(), b: u64(), c: u64(), d: u64(), e: u64(), f: u64(),
                g: optU64(), h: optU64(), name: compactString()
            ))
        }
        return output
    }
}

func registerSpanDecodeBenchmarks() {
    //  Full metric set so the receive-copy allocation/ARC is visible alongside the
    //  lead `instructions` count.
    let decodeMetrics: [BenchmarkMetric] =
        [.wallClock, .instructions, .throughput] + BenchmarkMetric.memory + BenchmarkMetric.arc
    for count in [100, 1000, 10000] {
        let received: [UInt8] = SpanWire.encodeBatch(count: count)
        Benchmark.init(
            "DecodeArrayCopy \(count)",
            configuration: .init(metrics: decodeMetrics, timeUnits: .microseconds)
        ) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try decodeArrayCopy(received, count: count))
            }
        }
        Benchmark.init(
            "DecodeSpanZeroCopy \(count)",
            configuration: .init(metrics: decodeMetrics, timeUnits: .microseconds)
        ) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try decodeSpanZeroCopy(received, count: count))
            }
        }
        Benchmark.init(
            "DecodeRawFloor \(count)",
            configuration: .init(metrics: decodeMetrics, timeUnits: .microseconds)
        ) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(decodeRawFloor(received, count: count))
            }
        }
    }
}
