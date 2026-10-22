import Foundation

extension Fuzz {
    /// The iterations and the seed of one fuzz test of one type.
    struct Run {
        let iterations: UInt64
        let seed: UInt64
        let type: String

        init(iterations: UInt64, seed: UInt64, type: String) {
            self.iterations = iterations
            self.seed = seed
            self.type = type
        }
    }
}
extension Fuzz.Run {
    /// A few thousand iterations from a fixed seed, unless the environment asks for more,
    /// in which case the seed is random unless the environment gives one too. A long run
    /// prints its seed first, so that a trap can be replayed as well as a failure.
    init<Value>(_: Value.Type) {
        let environment: [String: String] = ProcessInfo.processInfo.environment
        let iterations: UInt64? = environment["DISTRIBUTED_ABI_FUZZ_ITERATIONS"].flatMap {
            UInt64.init($0)
        }
        let seed: UInt64? = environment["DISTRIBUTED_ABI_FUZZ_SEED"].flatMap {
            $0.hasPrefix("0x") ? UInt64.init($0.dropFirst(2), radix: 16) : UInt64.init($0)
        }
        if  let iterations: UInt64 {
            self.init(
                iterations: iterations,
                seed: seed ?? .random(in: .min ... .max),
                type: "\(Value.self)"
            )
            print("fuzzing \(self.type) \(iterations) times from seed \(Self.hex(self.seed))")
        } else {
            self.init(
                iterations: 2_000,
                seed: seed ?? 0x0123_4567_89ab_cdef,
                type: "\(Value.self)"
            )
        }
    }

    /// The start of a failure message: the type and the seed that replays the iteration.
    func failure(seed: UInt64) -> String {
        """
        \(self.type), seed \(Self.hex(seed)) (replay with DISTRIBUTED_ABI_FUZZ_SEED=\
        \(Self.hex(seed)) DISTRIBUTED_ABI_FUZZ_ITERATIONS=1)
        """
    }

    private static func hex(_ seed: UInt64) -> String { "0x\(String.init(seed, radix: 16))" }
}
