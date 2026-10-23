import Benchmark
import DistributedABI

//  The two halves of `RoundtripDictionary?`, measured apart, over values of the same shape: the
//  read builds a dictionary of strings for every entry, which is most of the round trip and
//  hides any change to the write. The write sizes each value from `transferSize` and writes it
//  into one frame, reserved before the measurement for the largest value, as a send does, so
//  it leaves out the `[UInt8]` the round trip allocates for each value; the read decodes each
//  value from bytes written before the measurement, and keeps the values until the last, as the
//  round trip does. The contents are the same in every run, but the order of each dictionary’s
//  entries, in memory and on the wire, still follows the hash seed of the process.

func registerDictionaryBenchmarks() {
    let config: Benchmark.Configuration = .init(metrics: .default, timeUnits: .microseconds)

    Benchmark.init("WriteDictionary?", configuration: config) {
        (benchmark: Benchmark, fixture: (values: [[Int: [String: Int]]?], capacity: Int)) in
        let frame: UnsafeMutableRawBufferPointer = .allocate(
            byteCount: fixture.capacity,
            alignment: 16
        )
        defer {
            frame.deallocate()
        }
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            for dictionary: [Int: [String: Int]]? in fixture.values {
                blackHole(send(dictionary, into: frame))
            }
        }
    } setup: {
        let values: [[Int: [String: Int]]?] = dictionaries()
        return (values, values.reduce(0) { max($0, $1.transferSize) })
    }
    Benchmark.init("ReadDictionary?", configuration: config) {
        (benchmark: Benchmark, frames: [[UInt8]]) in
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(try read(frames, as: [Int: [String: Int]]?.self))
        }
    } setup: {
        dictionaries().map { [UInt8].init(transferring: $0) }
    }
}

//  The read half of `roundtrip(_:)`: each value is read back from its own `[UInt8]`.
@inline(never) func read<Value>(
    _ frames: [[UInt8]],
    as _: Value.Type
) throws(TransferError) -> [Value] where Value: Transferable {
    try frames.map { (frame: [UInt8]) throws(TransferError) -> Value in
        try .decode(frame)
    }
}

/// 101 dictionaries of 101 entries each, representative of CacheSynchronizationClientEndpoint
/// as those of `RoundtripDictionary?` are: every entry maps the same 101 strings to integers
/// that depend only on where they are, rather than to random ones.
func dictionaries() -> [[Int: [String: Int]]?] {
    let strings: [String] = (0 ... 100).map { String.init($0 * 131989, radix: 16) }
    let dictionaries: [[Int: [String: Int]]?] = (0 ... 100).map { (i: Int) in
        (0 ... 100).reduce(into: [:]) { (dictionary: inout [Int: [String: Int]], j: Int) in
            dictionary[j] = strings.indices.reduce(into: [:]) {
                let k: UInt64 = .init((i * 101 + j) * 101 + $1)
                let value: Int = .init(truncatingIfNeeded: k &* 0x9e37_79b9_7f4a_7c15)
                $0[strings[$1]] = value
            }
        }
    }
    precondition(debugRoundtripOK(dictionaries[0]), "dictionary roundtrip mismatch")
    return dictionaries
}
