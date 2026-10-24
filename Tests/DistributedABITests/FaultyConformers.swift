#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import DistributedABI
import Testing

/// A conformer that states a fixed size and reads more or fewer bytes is a fault of the
/// conformer, which a debug build of the caller stops at, wherever a collection reads the
/// element, and a release build does not look for. Each read below runs in a process of its own,
/// which must stop; a release build runs none of them.
@Suite enum FaultyConformers {
    @Test(.enabled(if: _isDebugAssertConfiguration())) static func ReadShort() async {
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? [Undersized].decode([1, 5, 6])
        }
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? [Undersized: UInt8].decode([1, 5, 6, 7])
        }
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? InlineArray<1, Undersized>.decode([5, 6])
        }
    }

    @Test(.enabled(if: _isDebugAssertConfiguration())) static func ReadLong() async {
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? [Overreader].decode([1, 5, 6])
        }
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? [Overreader: UInt8].decode([1, 5, 6, 7])
        }
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? [UInt8: Overreader].decode([1, 7, 5, 6])
        }
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? InlineArray<1, Overreader>.decode([5, 6])
        }
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? Batch<Overreader>.decode([1, 5, 6])
        }
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? Ledger<Overreader, UInt8>.decode([1, 5, 6, 7])
        }
    }

    /// An inline array of elements whose fixed size it cannot multiply states none, and reads
    /// each element through its own conformance, which still checks the element’s own size.
    @Test(.enabled(if: _isDebugAssertConfiguration())) static func ReadShortInsideAnInlineArray() async {
        await #expect(processExitsWith: .failure) {
            FaultyConformers.dumpNoCore()
            _ = try? [InlineArray<2, Oversized>].decode([1, 1, 2])
        }
    }

    /// The stop is expected, so the process that makes it writes no core file, which on a
    /// shared runner would take the disk and the time a crash report takes.
    static func dumpNoCore() {
        var limit: rlimit = .init(rlim_cur: 0, rlim_max: 0)
        _ = setrlimit(RLIMIT_CORE, &limit)
    }
}
