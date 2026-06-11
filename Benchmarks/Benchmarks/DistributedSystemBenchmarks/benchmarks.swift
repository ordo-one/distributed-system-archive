import Benchmark
import DistributedABI

@MainActor let benchmarks: () -> () = {
    Benchmark.defaultConfiguration.timeUnits = .microseconds
    Benchmark.defaultConfiguration.units = [
        .instructions: .kilo,
        .throughput: .count,
    ]
    Benchmark.init(
        "RoundtripInt",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        var ints: [Int] = [_].init(0 ... 10000)

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(ints))
        }
    }
    Benchmark.init(
        "RoundtripInt?",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        var ints: [Int?] = (0 ... 10000).map { $0 }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(ints))
        }
    }
    Benchmark.init(
        "RoundtripString",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        var strings: [String] = (0 ... 10000).map { String.init($0 * 131989, radix: 16) }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(strings))
        }
    }
    Benchmark.init(
        "RoundtripString?",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        var strings: [String?] = (0 ... 10000).map { String.init($0 * 131989, radix: 16) }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(strings))
        }
    }
    Benchmark.init(
        "RoundtripIntWire",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        var ints: [Int] = [_].init(0 ... 10000)

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtripWire(ints))
        }
    }
    Benchmark.init(
        "RoundtripIntBatch",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        var ints: [Int] = [_].init(0 ... 10000)

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtripBatch(ints))
        }
    }
    Benchmark.init(
        "RoundtripStringWire",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        var strings: [String] = (0 ... 10000).map { String.init($0 * 131989, radix: 16) }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtripWire(strings))
        }
    }
    Benchmark.init(
        "RoundtripStringBatch",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        var strings: [String] = (0 ... 10000).map { String.init($0 * 131989, radix: 16) }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtripBatch(strings))
        }
    }
    Benchmark.init(
        "RoundtripDictionary?",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        /// representative of CacheSynchronizationClientEndpoint
        let strings: [String] = (0 ... 100).map { String.init($0 * 131989, radix: 16) }
        var dictionaries: [[Int: [String: Int]]?] = (0 ... 100).map { _ in
            (0 ... 100).reduce(into: [:]) {
                let keys: [String] = strings.shuffled()
                $0[$1] = keys.reduce(into: [:]) {
                    $0[$1] = .random(in: .min ... .max)
                }
            }
        }

        let size: Int = dictionaries.reduce(0) {
            $0 + $1.withUnsafeBytesSerialization { $0.count }
        }
        print("total size: \(size)")

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(dictionaries))
        }
    }

    registerOldProductionDecode()
    registerOldProductionEncode()
    registerOrdoDictPayloads()
}

@inline(never) func roundtrip(_ values: [Int]) throws -> [Int] {
    try values.map {
        try $0.withUnsafeBytesSerialization(Int.init(fromSerializedBuffer:))
    }
}
@inline(never) func roundtrip(_ values: [Int?]) throws -> [Int?] {
    try values.map {
        try $0.withUnsafeBytesSerialization(Int?.init(fromSerializedBuffer:))
    }
}
@inline(never) func roundtrip(_ values: [String]) throws -> [String] {
    values.map {
        $0.withUnsafeBytesSerialization(String.init(fromSerializedBuffer:))
    }
}
@inline(never) func roundtrip(_ values: [String?]) throws -> [String?] {
    try values.map {
        try $0.withUnsafeBytesSerialization(String?.init(fromSerializedBuffer:))
    }
}
@inline(never) func roundtrip(
    _ values: [[Int: [String: Int]]?]
) throws -> [[Int: [String: Int]]?] {
    try values.map {
        try $0.withUnsafeBytesSerialization([Int: [String: Int]]?.init(fromSerializedBuffer:))
    }
}

// MARK: - wire-fair variants: include the copy into a send buffer that production performs

/// Per-element fresh wire buffer: the fair analog of the new system's per-element
/// `BufferEncoder(preallocated: [])` materialization. Production always copies the
/// serialized bytes into a send buffer (NIO ByteBuffer / LMDB page); the plain
/// `roundtrip(_:)` above skips that copy entirely and just casts a pointer.
@inline(never) func roundtripWire(_ values: [Int]) throws -> [Int] {
    try values.map {
        var wire: [UInt8] = []
        $0.withUnsafeBytesSerialization { wire.append(contentsOf: $0) }
        return try wire.withUnsafeBytes(Int.init(fromSerializedBuffer:))
    }
}
@inline(never) func roundtripWire(_ values: [String]) throws -> [String] {
    values.map {
        var wire: [UInt8] = []
        $0.withUnsafeBytesSerialization { wire.append(contentsOf: $0) }
        return wire.withUnsafeBytes(String.init(fromSerializedBuffer:))
    }
}

/// One shared wire buffer for the whole batch: the production message shape
/// (many fields encoded into a single send buffer, decoded sequentially).
@inline(never) func roundtripBatch(_ values: [Int]) throws -> [Int] {
    var wire: [UInt8] = []
    wire.reserveCapacity(values.count * 8)
    for value: Int in values {
        value.withUnsafeBytesSerialization { wire.append(contentsOf: $0) }
    }
    var output: [Int] = []
    output.reserveCapacity(values.count)
    try wire.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        for i: Int in 0 ..< values.count {
            output.append(
                try Int.init(fromSerializedBuffer: .init(rebasing: raw[i * 8 ..< (i + 1) * 8]))
            )
        }
    }
    return output
}
/// Variable-size elements need framing in the old system (the format is not
/// self-describing): a 4-byte length prefix per element, as a production
/// envelope would provide.
@inline(never) func roundtripBatch(_ values: [String]) throws -> [String] {
    var wire: [UInt8] = []
    for value: String in values {
        value.withUnsafeBytesSerialization {
            var size: UInt32 = .init($0.count)
            withUnsafeBytes(of: &size) { wire.append(contentsOf: $0) }
            wire.append(contentsOf: $0)
        }
    }
    var output: [String] = []
    output.reserveCapacity(values.count)
    wire.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        var index: Int = 0
        while index < raw.count {
            let size: Int = .init(raw.loadUnaligned(fromByteOffset: index, as: UInt32.self))
            index += 4
            output.append(
                String.init(fromSerializedBuffer: .init(rebasing: raw[index ..< index + size]))
            )
            index += size
        }
    }
    return output
}
