import Benchmark
import DistributedABI

//  Zero-copy ENCODE pricing for SpanEncoder (the encode-side mirror of SpanDecode).
//
//  This benchmark stacks on #23, which made `BufferEncoder` `[UInt8]`-backed. Producing
//  wire bytes for a NIO `ByteBuffer`, an LMDB `MDB_RESERVE` page, or any caller-reserved
//  region today means: encode into the encoder's owned `[UInt8]`, `finalize()`, then COPY
//  those bytes into the destination. So the fair post-#23 encode baseline is variant
//  (BASE): encode into a reused `BufferEncoder` and copy the finished bytes into a reused
//  `[UInt8]` send buffer (the send copy production pays). `SpanEncoder`'s whole point is to
//  remove that staging buffer and that copy by writing fields DIRECTLY into the reserved
//  region.
//
//  Three variants encode the SAME N messages into one buffer, swept 100/1000/10000 so the
//  copy cost shows as a slope. Only the encode (+ the send copy for BASE/G) is measured.
//
//  (BASE) EncodeBufferCopy    — current [UInt8] BufferEncoder + the send copy into a reused
//                               [UInt8] wire buffer. The post-#23 production encode path.
//  (R)    EncodeRawSpanReserve— OutputRawSpan straight into a reserved region allocated ONCE
//                               outside the measured region (the MDB_RESERVE /
//                               ByteBuffer.writeWithOutputRawSpan case). Per message: a cheap
//                               encodedSize() pass, then direct writes. No staging, no copy.
//  (G)    EncodeOutputSpanGrow— Array(capacity:initializingWith:) producing a [UInt8] like
//                               BASE, but the internal writes go through OutputSpan instead of
//                               Array.append. Still pays the send copy like BASE.

//  MARK: - The message (identical shape to SpanDecode's SpanBenchMessage).

/// 6x UInt64 + 2x UInt64? + a short identifier string — the shape a zero-copy encode entry
/// point would write to the wire. Encodes the SAME wire format through `BufferEncoder`
/// (the [UInt8] baseline), `SpanEncoder` (OutputRawSpan), and an OutputSpan growable path,
/// so all three are compared byte-for-byte.
struct SpanEncMessage: Equatable {
    var a: UInt64
    var b: UInt64
    var c: UInt64
    var d: UInt64
    var e: UInt64
    var f: UInt64
    var g: UInt64?
    var h: UInt64?
    var name: String

    /// Deterministic fixture so every variant encodes identical bytes.
    static func fixture(_ i: Int) -> SpanEncMessage {
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

    //  -- BASE: the production [UInt8] BufferEncoder encode (codegen-faithful). --
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

    //  -- decode through the production ArraySlice path (round-trip correctness). --
    static func decode(from input: inout BufferDecoder) throws -> SpanEncMessage {
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

    //  MARK: - encodedSize: the cheap size pass variant R needs to reserve EXACTLY.
    //
    //  Every field's wire size is a closed form: 8 per UInt64, 1 + (0 or 8) per UInt64?,
    //  and for the compact string 1 format byte + the UTF-8 byte count + 1 NUL (or 1 byte
    //  for the empty `.none` case). `name.utf8.count` is O(1) on a native string, so this
    //  stays a handful of adds — no recursion and no allocation. (See the report note on how
    //  this scales for NESTED variable-size types.)
    var encodedSize: Int {
        var n: Int = 8 * 6                       // a...f
        n += SpanEncMessage.optionalSize(self.g) // g
        n += SpanEncMessage.optionalSize(self.h) // h
        n += SpanEncMessage.stringSize(self.name)
        return n
    }

    static func optionalSize(_ v: UInt64?) -> Int {
        v == nil ? 1 : 1 + 8
    }

    /// Mirror of the `Substring` encode fast path: compact (<= 256 UTF-8 bytes, no NUL) is
    /// 1 format byte + bytes + 1 NUL; long is 1 + 4 + 1 + bytes; empty is 1 byte.
    static func stringSize(_ s: String) -> Int {
        let count: Int = s.utf8.count
        if count == 0 { return 1 }
        if count <= 256 && !s.utf8.contains(0) {
            return 2 + count
        }
        return 6 + count
    }

    //  MARK: - (R) direct write through SpanEncoder (OutputRawSpan). Same wire format.
    func encode(to output: inout SpanEncoder) {
        output.appendLittleEndian(self.a)
        output.appendLittleEndian(self.b)
        output.appendLittleEndian(self.c)
        output.appendLittleEndian(self.d)
        output.appendLittleEndian(self.e)
        output.appendLittleEndian(self.f)
        SpanEncMessage.encodeOptional(self.g, to: &output)
        SpanEncMessage.encodeOptional(self.h, to: &output)
        SpanEncMessage.encodeString(self.name, to: &output)
    }

    static func encodeOptional(_ v: UInt64?, to output: inout SpanEncoder) {
        if let v {
            output.append(1)                 // Optional.BinaryFormat.some
            output.appendLittleEndian(v)
        } else {
            output.append(0)                 // Optional.BinaryFormat.none
        }
    }

    static func encodeString(_ s: String, to output: inout SpanEncoder) {
        var local: String = s
        local.withUTF8 { (utf8: UnsafeBufferPointer<UInt8>) in
            if utf8.isEmpty {
                output.append(2)             // String.BinaryFormat.none
                return
            }
            if utf8.count <= 256 && !utf8.contains(0) {
                output.append(0)             // .compact
                output.append(copying: UnsafeRawBufferPointer(utf8))
                output.append(0x00)
            } else {
                let size: UInt64 = .init(utf8.count)
                output.append(1)             // .long
                output.appendLittleEndian(UInt32(truncatingIfNeeded: size))
                output.append(UInt8(size >> 32))
                output.append(copying: UnsafeRawBufferPointer(utf8))
            }
        }
    }
}

//  MARK: - Fixtures (built ONCE, outside any measured region).

enum SpanEncFixtures {
    static func batch(count: Int) -> [SpanEncMessage] {
        (0 ..< count).map(SpanEncMessage.fixture)
    }

    /// Worst case for the reserved region: every message the same exact maximum size so we
    /// can size the reserved page once. We instead size per-message via `encodedSize`, but
    /// we still need a single big reserved region for the whole batch.
    static func totalSize(_ messages: [SpanEncMessage]) -> Int {
        messages.reduce(0) { $0 + $1.encodedSize }
    }
}

//  MARK: - (BASE) [UInt8] BufferEncoder + send copy into a reused wire buffer.

@inline(never)
func encodeBufferCopy(_ messages: [SpanEncMessage], wire: inout [UInt8]) {
    //  One contiguous output buffer for the whole batch (the shape a batched send produces).
    //  Encode into a reused BufferEncoder with a zero-copy hand-off of the staging array,
    //  then copy the finished bytes into the reused `wire` send buffer — the copy production
    //  pays handing the encoder output to NIO / LMDB today.
    var staging: [UInt8] = []
    staging.reserveCapacity(wire.capacity)
    var encoder: BufferEncoder = .init(preallocated: staging)
    staging = []
    for message in messages {
        message.encode(to: &encoder)
    }
    let bytes: [UInt8] = encoder.finalize()
    //  The send copy: copy the encoded bytes into the reused wire region.
    wire.removeAll(keepingCapacity: true)
    wire.append(contentsOf: bytes)
    blackHole(wire.count)
}

//  MARK: - (R) OutputRawSpan straight into a reserved region (MDB_RESERVE case).

@inline(never)
func encodeRawSpanReserve(
    _ messages: [SpanEncMessage],
    reserved: UnsafeMutableRawBufferPointer
) {
    //  `reserved` is allocated ONCE outside the measured region (a reserved page / the NIO
    //  writable region). Per message: a cheap encodedSize() pass to know the exact extent,
    //  then write the fields DIRECTLY through an OutputRawSpan over the next slice of the
    //  reserved region. NO [UInt8] staging, NO send copy.
    var offset: Int = 0
    for message in messages {
        let size: Int = message.encodedSize
        let slice: UnsafeMutableRawBufferPointer = .init(
            rebasing: reserved[offset ..< offset + size]
        )
        let raw: OutputRawSpan = .init(buffer: slice, initializedCount: 0)
        var encoder: SpanEncoder = .init(raw)
        message.encode(to: &encoder)
        let written: Int = encoder.finalize()
        offset += written
    }
    blackHole(offset)
}

//  MARK: - (G) Array(capacity:initializingWith:) — OutputSpan internal writes, still produces
//  a [UInt8] and still pays the send copy.

@inline(never)
func encodeOutputSpanGrow(_ messages: [SpanEncMessage], wire: inout [UInt8]) {
    //  Same total-size pass as R (Array(capacity:initializingWith:) covers EXACTLY the
    //  requested count), but the writes go through OutputSpan<UInt8> instead of
    //  Array.append, to see whether the encoder's INTERNAL write path gets cheaper even when
    //  still producing an Array.
    let total: Int = messages.reduce(0) { $0 + $1.encodedSize }
    let produced: [UInt8] = .init(capacity: total) { (span: inout OutputSpan<UInt8>) in
        for message in messages {
            appendMessage(message, to: &span)
        }
    }
    //  The send copy, exactly as BASE pays it.
    wire.removeAll(keepingCapacity: true)
    wire.append(contentsOf: produced)
    blackHole(wire.count)
}

@inline(__always)
func appendLE<T: FixedWidthInteger & BitwiseCopyable>(_ value: T, to span: inout OutputSpan<UInt8>) {
    var le: T = value.littleEndian
    withUnsafeBytes(of: &le) { (raw: UnsafeRawBufferPointer) in
        for byte in raw { span.append(byte) }
    }
}

@inline(__always)
func appendMessage(_ m: SpanEncMessage, to span: inout OutputSpan<UInt8>) {
    appendLE(m.a, to: &span)
    appendLE(m.b, to: &span)
    appendLE(m.c, to: &span)
    appendLE(m.d, to: &span)
    appendLE(m.e, to: &span)
    appendLE(m.f, to: &span)
    appendOptional(m.g, to: &span)
    appendOptional(m.h, to: &span)
    appendString(m.name, to: &span)
}

@inline(__always)
func appendOptional(_ v: UInt64?, to span: inout OutputSpan<UInt8>) {
    if let v {
        span.append(1)
        appendLE(v, to: &span)
    } else {
        span.append(0)
    }
}

@inline(__always)
func appendString(_ s: String, to span: inout OutputSpan<UInt8>) {
    var local: String = s
    local.withUTF8 { (utf8: UnsafeBufferPointer<UInt8>) in
        if utf8.isEmpty {
            span.append(2)
            return
        }
        if utf8.count <= 256 && !utf8.contains(0) {
            span.append(0)
            for byte in utf8 { span.append(byte) }
            span.append(0x00)
        } else {
            let size: UInt64 = .init(utf8.count)
            span.append(1)
            appendLE(UInt32(truncatingIfNeeded: size), to: &span)
            span.append(UInt8(size >> 32))
            for byte in utf8 { span.append(byte) }
        }
    }
}

//  MARK: - (R size pass only) isolate the cost of the encodedSize() pre-pass.

@inline(never)
func encodeSizePassOnly(_ messages: [SpanEncMessage]) {
    var total: Int = 0
    for message in messages {
        total += message.encodedSize
    }
    blackHole(total)
}

//  MARK: - Correctness: R and G bytes must equal BASE bytes AND round-trip to the message.

/// Encode a batch through BASE into a fresh [UInt8].
func baseBytes(_ messages: [SpanEncMessage]) -> [UInt8] {
    var encoder: BufferEncoder = .init(capacity: SpanEncFixtures.totalSize(messages))
    for message in messages { message.encode(to: &encoder) }
    return [UInt8](encoder.output)
}

/// Encode a batch through R into a fresh [UInt8] (by copying out of the reserved region).
func rawSpanBytes(_ messages: [SpanEncMessage]) -> [UInt8] {
    let total: Int = SpanEncFixtures.totalSize(messages)
    let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: total, alignment: 1)
    defer { reserved.deallocate() }
    encodeRawSpanReserve(messages, reserved: reserved)
    return [UInt8](UnsafeRawBufferPointer(reserved))
}

/// Encode a batch through G into a fresh [UInt8].
func outputSpanBytes(_ messages: [SpanEncMessage]) -> [UInt8] {
    let total: Int = messages.reduce(0) { $0 + $1.encodedSize }
    return .init(capacity: total) { (span: inout OutputSpan<UInt8>) in
        for message in messages { appendMessage(message, to: &span) }
    }
}

/// Verify R and G are byte-identical to BASE and decode back to the originals.
func spanEncodeCorrect(_ messages: [SpanEncMessage]) -> Bool {
    let base: [UInt8] = baseBytes(messages)
    guard rawSpanBytes(messages) == base else { return false }
    guard outputSpanBytes(messages) == base else { return false }
    do {
        var decoder: BufferDecoder = .init(base[...])
        for original in messages {
            let decoded: SpanEncMessage = try .decode(from: &decoder)
            guard decoded == original else { return false }
        }
        try decoder.finish()
    } catch {
        return false
    }
    return true
}

//  MARK: - Registration.

func registerSpanEncodeBenchmarks() {
    //  Full metric set so the send-copy allocation/ARC is visible alongside the lead
    //  `instructions` count. The machine is BUSY; lead on instructions/malloc/retain only.
    let encodeMetrics: [BenchmarkMetric] =
        [.wallClock, .instructions, .throughput] + BenchmarkMetric.memory + BenchmarkMetric.arc

    for count in [100, 1000, 10000] {
        let messages: [SpanEncMessage] = SpanEncFixtures.batch(count: count)
        precondition(spanEncodeCorrect(messages), "SpanEncode \(count): variant bytes/round-trip mismatch")

        let total: Int = SpanEncFixtures.totalSize(messages)

        Benchmark.init(
            "EncodeBufferCopy \(count)",
            configuration: .init(metrics: encodeMetrics, timeUnits: .microseconds)
        ) { benchmark in
            var wire: [UInt8] = []
            wire.reserveCapacity(total)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                encodeBufferCopy(messages, wire: &wire)
            }
        }

        Benchmark.init(
            "EncodeRawSpanReserve \(count)",
            configuration: .init(metrics: encodeMetrics, timeUnits: .microseconds)
        ) { benchmark in
            //  The reserved page is allocated ONCE outside the measured region.
            let reserved: UnsafeMutableRawBufferPointer = .allocate(byteCount: total, alignment: 1)
            defer { reserved.deallocate() }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                encodeRawSpanReserve(messages, reserved: reserved)
            }
        }

        Benchmark.init(
            "EncodeOutputSpanGrow \(count)",
            configuration: .init(metrics: encodeMetrics, timeUnits: .microseconds)
        ) { benchmark in
            var wire: [UInt8] = []
            wire.reserveCapacity(total)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                encodeOutputSpanGrow(messages, wire: &wire)
            }
        }

        //  Isolate the cost of variant R's encodedSize() pre-pass so we can attribute how
        //  much of R's budget the two-pass costs vs how much the copy-avoidance saves.
        Benchmark.init(
            "EncodeSizePassOnly \(count)",
            configuration: .init(metrics: encodeMetrics, timeUnits: .microseconds)
        ) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                encodeSizePassOnly(messages)
            }
        }
    }
}
