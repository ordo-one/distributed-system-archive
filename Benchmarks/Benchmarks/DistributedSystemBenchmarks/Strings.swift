import Benchmark
import DistributedABI
#if _runtime(_ObjC)
import Foundation
#endif

//  A string write on its own, as the transport makes one for every string argument, element
//  or field: the size, then the bytes, into a frame the caller reserved. The round trips
//  measure the write together with the read and the allocation of the decoded string.

@inline(never) func write<Value>(
    _ values: [Value],
    into frame: UnsafeMutableRawBufferPointer
) -> Int where Value: Transferable {
    var output: OutputRawSpan = .init(buffer: frame, initializedCount: 0)
    for value: Value in values {
        precondition(value.transferSize <= output.freeCapacity, "frame too small")
        value.transfer(into: &output)
    }
    return output.finalize(for: frame)
}

func registerStringBenchmarks() {
    let config: Benchmark.Configuration = .init(metrics: .default, timeUnits: .microseconds)

    func register<Value>(_ name: String, _ values: [Value]) where Value: Transferable {
        let capacity: Int = values.reduce(0) { $0 + $1.transferSize }
        Benchmark.init(name, configuration: config) { benchmark in
            let frame: UnsafeMutableRawBufferPointer = .allocate(
                byteCount: max(capacity, 1),
                alignment: 16
            )
            defer {
                frame.deallocate()
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(write(values, into: frame))
            }
        }
    }

    //  one to eight bytes each, stored inline in the string
    register("WriteString", (0 ... 10000).map { String.init($0 * 131989, radix: 16) })
    //  native strings in a heap allocation of their own
    register(
        "WriteString 32 bytes",
        (0 ... 10000).map {
            let digits: String = .init($0 * 131989, radix: 16)
            return String.init(repeating: "x", count: 32 - digits.count) + digits
        }
    )

    #if _runtime(_ObjC)
    //  The last character of a string bridged from an `NSString` with UTF-16 contents: the
    //  write costs the same however much text precedes the substring.
    for backing: Int in [10_000, 1_000_000] {
        let string: String = bridgedString(count: backing)
        precondition(!string.isContiguousUTF8, "the string must stay bridged")
        register("WriteBridgedSuffix \(backing)", [string.suffix(1)])
    }
    #endif
}

#if _runtime(_ObjC)
/// A string of `count` UTF-16 code units, each “é”, bridged lazily from an `NSString`, so
/// its UTF-8 view is not contiguous.
func bridgedString(count: Int) -> String {
    let units: [UInt16] = .init(repeating: 0xe9, count: count)
    let string: NSString = units.withUnsafeBufferPointer {
        NSString.init(characters: $0.baseAddress!, length: $0.count)
    }
    return string as String
}
#endif
