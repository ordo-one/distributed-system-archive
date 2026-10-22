import DistributedABI
import Testing

/// Seeded fuzz tests: random values of nested types round-trip, and random, truncated and
/// mutated bytes either decode or are refused, never trap.
///
/// A quick run takes a few thousand iterations per type. A long run, for a nightly job, sets
/// `DISTRIBUTED_ABI_FUZZ_ITERATIONS` to the number of iterations per type and draws a random
/// seed unless `DISTRIBUTED_ABI_FUZZ_SEED` gives one. Every failure states its iteration, the
/// seed that replays it as `DISTRIBUTED_ABI_FUZZ_SEED=<seed> DISTRIBUTED_ABI_FUZZ_ITERATIONS=1`,
/// and every byte of its input. A trap ends the process before the test can report it, so a
/// long run keeps the iteration in progress in a file it names as it starts; a trap in a quick
/// run recurs in a long run of 2,000 iterations from the quick run’s seed, 0x0123456789abcdef.
///
/// A set or a dictionary writes its elements in its iteration order, which differs from one
/// process to the next, so the truncations and mutations start from the valid encoding with
/// the elements of every set and the entries of every dictionary in the order of their bytes,
/// and a seed replays the same bytes in any process. A round trip from a replayed seed writes
/// the same value, in an order that may differ, which is why its failure keeps the bytes.
@Suite enum Fuzz {
    /// A random value writes exactly the bytes it states into a buffer of that size, and reads
    /// back as the same value from all of them.
    @Test(arguments: Self.types) static func RandomValues(_ type: any Fuzzable.Type) {
        Self.randomValues(type)
    }

    /// Random bytes, and truncations and single-byte mutations of a valid encoding, either
    /// decode or throw a ``TransferError``; a value that decodes writes back exactly the bytes
    /// it read, up to the order of the elements of a set and the entries of a dictionary.
    @Test(arguments: Self.types) static func MalformedBytes(_ type: any Fuzzable.Type) {
        Self.malformedBytes(type)
    }
}
extension Fuzz {
    private static var types: [any Fuzzable.Type] {
        [
            Int8.self,
            Int16.self,
            Int32.self,
            Int64.self,
            Int.self,
            Int128.self,
            UInt8.self,
            UInt16.self,
            UInt32.self,
            UInt64.self,
            UInt.self,
            UInt128.self,
            Bool.self,
            Float.self,
            Double.self,
            String.self,
            Side.self,
            Venue.self,
            Identifier.self,
            Int32?.self,
            String?.self,
            Double?.self,
            [UInt16].self,
            [String].self,
            [Double].self,
            [[Int8]].self,
            [Identifier].self,
            [Venue?].self,
            Set<Int64>.self,
            Set<String>.self,
            Set<Identifier>.self,
            Set<Set<UInt8>>.self,
            [String: Int32].self,
            [UInt8: [String]].self,
            [Identifier: Double?].self,
            Result<String, Failure>.self,
            Result<[Int16], Failure>.self,
            [String: [Set<Int16>?]].self,
            [Result<[UInt32: String], Failure>?].self,
        ]
    }

    /// The elements every random value may hold in all its collections together.
    private static var budget: Int { 160 }

    /// The number of elements of a random collection: mostly a few, sometimes more than 127,
    /// so that the count takes two ULEB128 bytes, and never more than the budget left.
    static func count(using random: inout SplitMix64, budget: inout Int) -> Int {
        let count: Int = Int.random(in: 0 ..< 16, using: &random) == 0
            ? .random(in: 0 ... 140, using: &random)
            : .random(in: 0 ... 4, using: &random)
        let spent: Int = min(count, budget)
        budget -= spent
        return spent
    }
}
extension Fuzz {
    private static func randomValues<Value>(_: Value.Type) where Value: Fuzzable {
        let run: Run = .init(Value.self, test: "RandomValues")
        defer {
            run.finish()
        }
        for i: UInt64 in 0 ..< run.iterations {
            run.start(i)
            var random: SplitMix64 = .init(seed: run.seed(i))
            var budget: Int = Self.budget
            let value: Value = .random(using: &random, budget: &budget)
            let bytes: [UInt8] = .init(transferring: value)
            let failure: String?
            if  bytes.count != value.transferSize {
                let stated: Int = value.transferSize
                failure = "wrote \(bytes.count) bytes \(Self.hex(bytes)), but states \(stated)"
            } else {
                failure = Self.reading(Value.self, value, from: bytes)
            }
            if  let failure: String {
                Issue.record("\(run.failure(i)): \(Self.describe(value)): \(failure)")
                return
            }
        }
    }

    private static func reading<Value>(
        _: Value.Type,
        _ value: Value,
        from bytes: [UInt8]
    ) -> String? where Value: Fuzzable {
        var input: TransferReader = .init(bytes.span.bytes)
        let decoded: Value
        do {
            decoded = try .init(transferring: &input)
        } catch {
            return "refused its own bytes \(Self.hex(bytes)): \(error)"
        }
        if  input.remaining != 0 {
            return "left \(input.remaining) of its bytes \(Self.hex(bytes)) unread"
        }
        if !Value.same(decoded, value) {
            return "read back as \(Self.describe(decoded)) from \(Self.hex(bytes))"
        }
        return Self.rewriting(decoded, of: bytes)
    }
}
extension Fuzz {
    private static func malformedBytes<Value>(_: Value.Type) where Value: Fuzzable {
        let run: Run = .init(Value.self, test: "MalformedBytes")
        defer {
            run.finish()
        }
        for i: UInt64 in 0 ..< run.iterations {
            run.start(i)
            var random: SplitMix64 = .init(seed: run.seed(i))

            let count: Int = Int.random(in: 0 ..< 8, using: &random) == 0
                ? .random(in: 0 ... 64, using: &random)
                : .random(in: 0 ... 12, using: &random)
            let noise: [UInt8] = (0 ..< count).map {
                _ in
                .random(in: 0 ... 255, using: &random)
            }

            var budget: Int = Self.budget
            let value: Value = .random(using: &random, budget: &budget)
            let written: [UInt8] = .init(transferring: value)
            guard
            let valid: [UInt8] = Value.shape.canonical(written) else {
                let bytes: String = Self.hex(written)
                Issue.record(
                    "\(run.failure(i)): \(Self.describe(value)) wrote \(bytes), not of its shape"
                )
                return
            }
            var truncated: [UInt8] = []
            var mutated: [UInt8] = []
            if !valid.isEmpty {
                truncated = .init(valid[..<Int.random(in: valid.indices, using: &random)])
                mutated = valid
                mutated[Int.random(in: valid.indices, using: &random)] ^= .random(
                    in: 1 ... 255,
                    using: &random
                )
            }

            for (kind, bytes): (String, [UInt8]) in [
                    ("random bytes", noise),
                    ("truncated", truncated),
                    ("mutated", mutated),
                ] {
                if  let failure: String = Self.decoding(Value.self, from: bytes) {
                    Issue.record("\(run.failure(i)): \(kind) \(Self.hex(bytes)): \(failure)")
                    return
                }
            }
        }
    }

    /// Nil if `bytes` decode to a value that writes back the bytes it read, or are refused.
    private static func decoding<Value>(
        _: Value.Type,
        from bytes: [UInt8]
    ) -> String? where Value: Fuzzable {
        var input: TransferReader = .init(bytes.span.bytes)
        let value: Value
        do {
            value = try .init(transferring: &input)
        } catch {
            return nil
        }
        return Self.rewriting(value, of: .init(bytes[..<(bytes.count - input.remaining)]))
    }

    /// Nil if `value` writes the bytes it states, and they are `bytes` up to the order of the
    /// elements of a set and the entries of a dictionary.
    private static func rewriting<Value>(
        _ value: Value,
        of bytes: [UInt8]
    ) -> String? where Value: Fuzzable {
        let written: [UInt8] = .init(transferring: value)
        if  written.count != value.transferSize {
            let stated: Int = value.transferSize
            return "\(Self.describe(value)) wrote \(written.count) bytes, but states \(stated)"
        }
        if  written == bytes {
            return nil
        }
        if  let canonical: [UInt8] = Value.shape.canonical(written),
            case canonical? = Value.shape.canonical(bytes) {
            return nil
        }
        return "\(Self.describe(value)) read \(Self.hex(bytes)) but writes \(Self.hex(written))"
    }

    private static func describe(_ value: some Fuzzable) -> String {
        let description: String = "\(value)"
        return description.count > 200 ? "\(description.prefix(200))…" : description
    }

    /// Every byte, so that a failure carries the whole of the input that reproduces it.
    private static func hex(_ bytes: [UInt8]) -> String {
        let digits: String = bytes.map {
            $0 < 0x10 ? "0\(String.init($0, radix: 16))" : String.init($0, radix: 16)
        }.joined()
        return "[\(digits)]"
    }
}
