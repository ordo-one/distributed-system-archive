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
        let ints: [Int] = [_].init(0 ... 10000)

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(ints))
        }
    }
    Benchmark.init(
        "RoundtripInt?",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        let ints: [Int?] = (0 ... 10000).map { $0 }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(ints))
        }
    }
    Benchmark.init(
        "RoundtripString",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        let strings: [String] = (0 ... 10000).map { String.init($0 * 131989, radix: 16) }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(strings))
        }
    }
    Benchmark.init(
        "RoundtripString?",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        let strings: [String?] = (0 ... 10000).map { String.init($0 * 131989, radix: 16) }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(strings))
        }
    }
    Benchmark.init(
        "RoundtripIntBatch",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        let ints: [Int] = [_].init(0 ... 10000)

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtripBatch(ints))
        }
    }
    Benchmark.init(
        "RoundtripStringBatch",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        let strings: [String] = (0 ... 10000).map { String.init($0 * 131989, radix: 16) }

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
        let dictionaries: [[Int: [String: Int]]?] = (0 ... 100).map { _ in
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
}

@inline(never) func roundtrip(_ values: [Int]) throws -> [Int] {
    try values.map { try Int.decode($0.encoded()) }
}
@inline(never) func roundtrip(_ values: [Int?]) throws -> [Int?] {
    try values.map { try Int?.decode($0.encoded()) }
}
@inline(never) func roundtrip(_ values: [String]) throws -> [String] {
    try values.map { try String.decode($0.encoded()) }
}
@inline(never) func roundtrip(_ values: [String?]) throws -> [String?] {
    try values.map { try String?.decode($0.encoded()) }
}
@inline(never) func roundtrip(_ values: [[Int: [String: Int]]?]) throws -> [[Int: [String: Int]]?] {
    try values.map { try [Int: [String: Int]]?.decode($0.encoded()) }
}

// MARK: - batched variants: one shared buffer for the whole batch, the production
// message shape (many fields encoded into a single send buffer, decoded sequentially).
// Amortizes the encode allocation across all elements.

@inline(never) func roundtripBatch(_ values: [Int]) throws -> [Int] {
    let wire: [UInt8] = values.encoded()
    return try [Int].decode(wire)
}
@inline(never) func roundtripBatch(_ values: [String]) throws -> [String] {
    let wire: [UInt8] = values.encoded()
    return try [String].decode(wire)
}
