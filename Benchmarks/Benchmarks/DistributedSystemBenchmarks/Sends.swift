import Benchmark
import DistributedABI

//  A send as the transport makes one: the frame is sized from `transferSize`, then the value
//  is written into it through `transfer(into:)`. Each collection holds 16 messages of 316
//  bytes, the size of an SDK transaction, whose bytes live in a class instance, so every copy
//  of an element costs a retain and a release. The arrays of built messages hold 1 and 100
//  messages of 316 bytes that build their bytes on every lend, as a computed-property table
//  does, so they measure the lends a send makes.

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

    func register<Value>(_ name: String, _ value: Value) where Value: Transferable {
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
}
