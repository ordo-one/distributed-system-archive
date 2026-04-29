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
