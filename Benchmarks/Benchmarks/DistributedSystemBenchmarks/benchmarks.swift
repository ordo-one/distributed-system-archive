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
