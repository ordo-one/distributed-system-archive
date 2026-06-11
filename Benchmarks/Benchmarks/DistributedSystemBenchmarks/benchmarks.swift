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

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(dictionaries))
        }
    }

    // Production-representative payload benchmarks (see Payloads.swift).
    registerPayloadBenchmarks()

    // Zero-copy decode pricing: SpanDecoder vs the post-#23 baseline (see SpanDecode.swift).
    registerSpanDecodeBenchmarks()

    // Zero-copy encode pricing: SpanEncoder vs the post-#23 baseline (see SpanEncode.swift).
    registerSpanEncodeBenchmarks()

    // Ordo runtime RPC dictionary payloads: #23 vs #24 (see OrdoDictPayloads.swift).
    registerOrdoDictBenchmarks()

    // Trading-quoter big payload: Codable/JSON (today) vs #23 vs #24 (see QuoteTablePayload.swift).
    registerQuoteTableBenchmarks()

    // Computed-property live values (BestPrice/MarketData): JSON (today) vs #23 vs #24 (see CPSPayload.swift).
    registerCPSPayloadBenchmarks()
}

@inline(never) func roundtrip(_ values: [Int]) throws -> [Int] {
    try values.map {
        var encoder: BufferEncoder = .init(preallocated: [])
        try $0.encode(to: &encoder)
        var decoder: BufferDecoder = .init(encoder.output)
        return try .decode(from: &decoder)
    }
}
@inline(never) func roundtrip(_ values: [Int?]) throws -> [Int?] {
    try values.map {
        var encoder: BufferEncoder = .init(preallocated: [])
        try $0.encode(to: &encoder)
        var decoder: BufferDecoder = .init(encoder.output)
        return try .decode(from: &decoder)
    }
}
@inline(never) func roundtrip(_ values: [String]) throws -> [String] {
    try values.map {
        var encoder: BufferEncoder = .init(preallocated: [])
        try $0.encode(to: &encoder)
        var decoder: BufferDecoder = .init(encoder.output)
        return try .decode(from: &decoder)
    }
}
@inline(never) func roundtrip(_ values: [String?]) throws -> [String?] {
    try values.map {
        var encoder: BufferEncoder = .init(preallocated: [])
        try $0.encode(to: &encoder)
        var decoder: BufferDecoder = .init(encoder.output)
        return try .decode(from: &decoder)
    }
}
@inline(never) func roundtrip(_ values: [[Int: [String: Int]]?]) throws -> [[Int: [String: Int]]?] {
    try values.map {
        var encoder: BufferEncoder = .init(preallocated: [])
        try $0.encode(to: &encoder)
        var decoder: BufferDecoder = .init(encoder.output)
        return try .decode(from: &decoder)
    }
}

// MARK: - batched variants: one shared buffer for the whole batch, the production
// message shape (many fields encoded into a single send buffer, decoded sequentially).
// Amortizes the encoder allocation across all elements.

@inline(never) func roundtripBatch(_ values: [Int]) throws -> [Int] {
    var encoder: BufferEncoder = .init(capacity: values.count * 8)
    for value: Int in values {
        value.encode(to: &encoder)
    }
    var decoder: BufferDecoder = .init(encoder.output)
    var output: [Int] = []
    output.reserveCapacity(values.count)
    for _ in 0 ..< values.count {
        output.append(try .decode(from: &decoder))
    }
    return output
}
@inline(never) func roundtripBatch(_ values: [String]) throws -> [String] {
    var encoder: BufferEncoder = .init(capacity: 16 * values.count)
    for value: String in values {
        value.encode(to: &encoder)
    }
    var decoder: BufferDecoder = .init(encoder.output)
    var output: [String] = []
    output.reserveCapacity(values.count)
    for _ in 0 ..< values.count {
        output.append(try .decode(from: &decoder))
    }
    return output
}
