import Benchmark
import DistributedABI

//  "Current production" decode of the same 9-field message shape used by the
//  SpanDecoder benchmark on the new branch, via the OLD `Deserializable`
//  (`init(fromSerializedBuffer:)`) API that ships today.
//
//  The old system has no self-framing composite decode — `init(fromSerializedBuffer:)`
//  consumes a whole buffer per value — so the runtime supplies per-argument length
//  framing (RemoteCallEncoder/Decoder). We model that faithfully: each field is encoded
//  to its old serialized bytes and prefixed with a 1-byte length (every field here is
//  < 128 bytes, so a single byte is the ULEB128 form the runtime would emit), then
//  decode reads each length and calls the old per-field `init(fromSerializedBuffer:)`.
//
//  Same message SHAPE as the new-branch SpanBenchMessage (the old/new wire formats
//  differ, so the bytes are not identical — this measures decode COST for the shape,
//  not byte parity).

struct OldMessage {
    var a: UInt64, b: UInt64, c: UInt64, d: UInt64, e: UInt64, f: UInt64
    var g: UInt64?, h: UInt64?
    var name: String

    static func fixture(_ i: Int) -> OldMessage {
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
}

//  MARK: - Encode: per-field old serialization, each length-prefixed (runtime framing).

@inline(__always) private func appendFramed(
    _ value: some Serializable, to wire: inout [UInt8]
) {
    value.withUnsafeBytesSerialization { (bytes: UnsafeRawBufferPointer) in
        wire.append(UInt8(bytes.count))   // 1-byte length (all fields < 128 bytes)
        wire.append(contentsOf: bytes)
    }
}

enum OldWire {
    static func encodeBatch(count: Int) -> [UInt8] {
        var wire: [UInt8] = []
        wire.reserveCapacity(count * 96)
        for i in 0 ..< count {
            let m = OldMessage.fixture(i)
            appendFramed(m.a, to: &wire); appendFramed(m.b, to: &wire)
            appendFramed(m.c, to: &wire); appendFramed(m.d, to: &wire)
            appendFramed(m.e, to: &wire); appendFramed(m.f, to: &wire)
            appendFramed(m.g, to: &wire); appendFramed(m.h, to: &wire)
            appendFramed(m.name, to: &wire)
        }
        return wire
    }
}

//  MARK: - Decode: read each 1-byte length, decode the slice via the old API.

@inline(never) func decodeOldProduction(_ received: [UInt8], count: Int) throws -> [OldMessage] {
    try received.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [OldMessage] in
        var i: Int = 0
        func field<T: Deserializable>(_ type: T.Type) throws -> T {
            let len = Int(raw[i]); i += 1
            let slice = UnsafeRawBufferPointer(rebasing: raw[i ..< i + len])
            i += len
            return try T(fromSerializedBuffer: slice)
        }
        var output: [OldMessage] = []
        output.reserveCapacity(count)
        for _ in 0 ..< count {
            output.append(OldMessage(
                a: try field(UInt64.self), b: try field(UInt64.self),
                c: try field(UInt64.self), d: try field(UInt64.self),
                e: try field(UInt64.self), f: try field(UInt64.self),
                g: try field(UInt64?.self), h: try field(UInt64?.self),
                name: try field(String.self)
            ))
        }
        return output
    }
}

func registerOldProductionDecode() {
    let metrics: [BenchmarkMetric] =
        [.wallClock, .instructions, .throughput] + BenchmarkMetric.memory + BenchmarkMetric.arc
    for count in [100, 1000, 10000] {
        let received: [UInt8] = OldWire.encodeBatch(count: count)
        Benchmark.init(
            "DecodeOldProduction \(count)",
            configuration: .init(metrics: metrics, timeUnits: .microseconds)
        ) { benchmark in
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try decodeOldProduction(received, count: count))
            }
        }
    }
}

//  MARK: - "Current production" ENCODE of the same message shape.
//
//  The old system serializes each field via withUnsafeBytesSerialization and the runtime
//  frames (length prefix) + writes the bytes into the send buffer. We model that: per
//  message, per field, append a 1-byte length + the field's old serialized bytes into a
//  REUSED [UInt8] wire buffer (the send buffer). No separate encoder/staging step exists in
//  the old design — serialization writes straight into the destination via the closure.

@inline(never) func encodeOldProduction(_ messages: [OldMessage], wire: inout [UInt8]) {
    wire.removeAll(keepingCapacity: true)
    for m in messages {
        appendFramed(m.a, to: &wire); appendFramed(m.b, to: &wire)
        appendFramed(m.c, to: &wire); appendFramed(m.d, to: &wire)
        appendFramed(m.e, to: &wire); appendFramed(m.f, to: &wire)
        appendFramed(m.g, to: &wire); appendFramed(m.h, to: &wire)
        appendFramed(m.name, to: &wire)
    }
}

func registerOldProductionEncode() {
    let metrics: [BenchmarkMetric] =
        [.wallClock, .instructions, .throughput] + BenchmarkMetric.memory + BenchmarkMetric.arc
    for count in [100, 1000, 10000] {
        let messages: [OldMessage] = (0 ..< count).map(OldMessage.fixture)
        Benchmark.init(
            "EncodeOldProduction \(count)",
            configuration: .init(metrics: metrics, timeUnits: .microseconds)
        ) { benchmark in
            var wire: [UInt8] = []
            wire.reserveCapacity(count * 96)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                encodeOldProduction(messages, wire: &wire)
                blackHole(wire.count)
            }
        }
    }
}
