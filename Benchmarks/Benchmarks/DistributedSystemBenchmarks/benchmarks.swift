import Benchmark
import DistributedABI

// Not main-actor isolated: the harness calls it from its nonisolated `registerBenchmarks()`,
// which Swift 6.4 refuses for a main-actor `let`.
let benchmarks: @Sendable () -> () = {
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
        let frame: UnsafeMutableRawBufferPointer = .allocate(
            byteCount: ints.reduce(0) { max($0, $1.transferSize) },
            alignment: 16
        )
        defer {
            frame.deallocate()
        }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(ints, frame: frame))
        }
    }
    Benchmark.init(
        "RoundtripInt?",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        let ints: [Int?] = (0 ... 10000).map { $0 }
        let frame: UnsafeMutableRawBufferPointer = .allocate(
            byteCount: ints.reduce(0) { max($0, $1.transferSize) },
            alignment: 16
        )
        defer {
            frame.deallocate()
        }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(ints, frame: frame))
        }
    }
    Benchmark.init(
        "RoundtripString",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        let strings: [String] = (0 ... 10000).map { String.init($0 * 131989, radix: 16) }
        let frame: UnsafeMutableRawBufferPointer = .allocate(
            byteCount: strings.reduce(0) { max($0, $1.transferSize) },
            alignment: 16
        )
        defer {
            frame.deallocate()
        }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(strings, frame: frame))
        }
    }
    Benchmark.init(
        "RoundtripString?",
        configuration: .init(metrics: .default, timeUnits: .microseconds)
    ) {
        let strings: [String?] = (0 ... 10000).map { String.init($0 * 131989, radix: 16) }
        let frame: UnsafeMutableRawBufferPointer = .allocate(
            byteCount: strings.reduce(0) { max($0, $1.transferSize) },
            alignment: 16
        )
        defer {
            frame.deallocate()
        }

        $0.startMeasurement()

        for _ in $0.scaledIterations {
            blackHole(try roundtrip(strings, frame: frame))
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

    // The write and the read of `RoundtripDictionary?` apart (see Dictionaries.swift).
    registerDictionaryBenchmarks()
    // Production-representative payload benchmarks (see Payloads.swift).
    registerPayloadBenchmarks()
    // String writes on their own (see Strings.swift).
    registerStringBenchmarks()
    // Sends of class-backed messages (see Sends.swift).
    registerSendBenchmarks()
}

//  Each value is written into one frame allocated before the measurement and read back from
//  it, as the transport writes a value into a frame and reads it from there, so the row counts
//  the codec and not an allocation per value.
@inline(never) func roundtrip<Value>(
    _ values: [Value],
    frame: UnsafeMutableRawBufferPointer
) throws(TransferError) -> [Value] where Value: Transferable {
    try values.map { (value: Value) throws(TransferError) -> Value in
        var output: OutputRawSpan = .init(buffer: frame, initializedCount: 0)
        value.transfer(into: &output)
        let decoded: Value
        do {
            var input: TransferReader = .init(output.bytes)
            decoded = try .init(transferring: &input)
            try input.finish()
        }
        _ = output.finalize(for: frame)
        return decoded
    }
}

//  Each value becomes its own `[UInt8]`, sized from `transferSize`, and is read back from it,
//  the shape #23 measured: the wire buffer is part of the cost.
@inline(never) func roundtrip<Value>(
    _ values: [Value]
) throws(TransferError) -> [Value] where Value: Transferable {
    try values.map { (value: Value) throws(TransferError) -> Value in
        try .decode(.init(transferring: value))
    }
}

//  The whole batch travels as one array in one buffer: a count, then the elements, packed when
//  they have a fixed size and each behind its ULEB128 length otherwise.
@inline(never) func roundtripBatch<Value>(
    _ values: [Value]
) throws(TransferError) -> [Value] where Value: Transferable {
    try .decode(.init(transferring: values))
}
