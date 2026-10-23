import Benchmark
import DistributedABI

//  A send as the transport makes one: the frame is sized from `transferSize`, then the value
//  is written into it through `transfer(into:)`. Each collection holds 16 messages of 316
//  bytes, the size of an SDK transaction, whose bytes live in a class instance, so every copy
//  of an element costs a retain and a release. The arrays of built messages hold 1 and 100
//  messages of 316 bytes that build their bytes on every lend, as a computed-property table
//  does, so they measure the lends a send makes. The arrays of strings hold the same 256 short
//  strings at three depths: flat, in 16 arrays of 16, and in 4 arrays of 4 arrays of 16, so a
//  cost that grows with the depth shows against the flat array. The nested dictionary holds 16
//  arrays of 16 class-backed messages, by key.

@inline(never) func send<Value>(
    _ value: Value,
    into frame: UnsafeMutableRawBufferPointer
) -> Int where Value: Transferable {
    let size: Int = value.transferSize
    precondition(size <= frame.count, "frame too small")
    let buffer: UnsafeMutableRawBufferPointer = .init(rebasing: frame[..<size])
    var output: OutputRawSpan = .init(buffer: buffer, initializedCount: 0)
    value.transfer(into: &output)
    return output.finalize(for: buffer)
}

func registerSendBenchmarks() {
    let config: Benchmark.Configuration = .init(
        metrics: .default,
        timeUnits: .microseconds,
        scalingFactor: .kilo
    )

    func register<Value>(_ name: String, _ value: Value) where Value: Transferable & Equatable {
        precondition(debugRoundtripOK(value), "\(name) roundtrip mismatch")
        let capacity: Int = value.transferSize
        Benchmark.init(name, configuration: config) { benchmark in
            let frame: UnsafeMutableRawBufferPointer = .allocate(
                byteCount: capacity,
                alignment: 16
            )
            defer {
                frame.deallocate()
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(send(value, into: frame))
            }
        }
    }

    let messages: [Message] = (0 ..< 16).map {
        .init(bytes: .init(repeating: UInt8.init($0), count: 316))
    }
    register("SendArray class x16", messages)
    register("SendArraySlice class x16", messages[...])
    register("SendSet class x16", Set<Message>.init(messages))
    register(
        "SendDictionary class x16",
        [UInt64: Message].init(
            uniqueKeysWithValues: messages.enumerated().map { (UInt64.init($0), $1) }
        )
    )

    let built: [Built] = (0 ..< 100).map { (i: Int) in
        .init(fields: (0 ..< 39).map { UInt64.init(i * 39 + $0) &* 0x9e37_79b9_7f4a_7c15 })
    }
    register("SendArray built x1", [built[0]])
    register("SendArray built x100", built)

    let strings: [String] = (0 ..< 256).map { String.init($0 * 131989, radix: 16) }
    let arrays: [[String]] = stride(from: 0, to: 256, by: 16).map {
        .init(strings[$0 ..< $0 + 16])
    }
    register("SendArray string x256", strings)
    register("SendArray string x16x16", arrays)
    register(
        "SendArray string x4x4x16",
        stride(from: 0, to: 16, by: 4).map { [[String]].init(arrays[$0 ..< $0 + 4]) }
    )
    register(
        "SendDictionary class x16x16",
        [UInt64: [Message]].init(
            uniqueKeysWithValues: (0 ..< 16).map { (key: Int) in
                let messages: [Message] = (0 ..< 16).map {
                    .init(bytes: .init(repeating: UInt8.init(key * 16 + $0), count: 316))
                }
                return (UInt64.init(key), messages)
            }
        )
    )
}
