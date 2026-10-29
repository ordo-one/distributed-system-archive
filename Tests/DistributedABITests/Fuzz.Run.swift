import Foundation

extension Fuzz {
    /// The iterations and the seed of one fuzz test of one type.
    struct Run {
        let iterations: UInt64
        let seed: UInt64
        let type: String
        /// In a long run, the file that names the iteration in progress, and its path.
        let progress: (file: FileHandle, path: String)?

        init(
            iterations: UInt64,
            seed: UInt64,
            type: String,
            progress: (file: FileHandle, path: String)?
        ) {
            self.iterations = iterations
            self.seed = seed
            self.type = type
            self.progress = progress
        }
    }
}
extension Fuzz.Run {
    /// A few thousand iterations from a fixed seed, unless the environment asks for more,
    /// in which case the seed is random unless the environment gives one too. A long run
    /// prints its seed first, and keeps the iteration in progress in a file it names, so
    /// that a trap, which ends the process before the test can report it, can be replayed
    /// as well as a failure.
    init<Value>(_: Value.Type, test: String) {
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
                type: "\(Value.self)",
                progress: Self.progress(test: test, type: "\(Value.self)")
            )
            let progress: String = self.progress.map {
                ", the iteration in progress in \($0.path)"
            } ?? ""
            let seed: String = Self.hex(self.seed)
            print("fuzzing \(self.type) \(iterations) times from seed \(seed)\(progress)")
        } else {
            self.init(
                iterations: 2_000,
                seed: seed ?? 0x0123_4567_89ab_cdef,
                type: "\(Value.self)",
                progress: nil
            )
        }
    }

    /// A file named for the test and the type in a directory of the temporary directory,
    /// empty and open for writing; nil if it cannot be made.
    private static func progress(test: String, type: String) -> (
        file: FileHandle,
        path: String
    )? {
        let directory: URL = FileManager.default.temporaryDirectory.appending(
            path: "distributed-abi-fuzz",
            directoryHint: .isDirectory
        )
        let name: String = .init(
            "\(test) \(type)".map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" }
        )
        let path: String = directory.appending(path: "\(name).txt").path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        guard FileManager.default.createFile(atPath: path, contents: nil),
        let file: FileHandle = .init(forWritingAtPath: path) else {
            return nil
        }
        return (file, path)
    }
}
extension Fuzz.Run {
    /// The seed of iteration `i`, which replays it as the only iteration of a run.
    func seed(_ i: UInt64) -> UInt64 { self.seed &+ i }

    /// Records, in a long run, that iteration `i` begins. The record never gets shorter, as
    /// the seeds have all their digits and the iterations count up, so writing it over the
    /// last one leaves nothing of that behind.
    func start(_ i: UInt64) {
        guard
        let (file, _): (FileHandle, String) = self.progress else {
            return
        }
        try? file.seek(toOffset: 0)
        try? file.write(contentsOf: Data.init("\(self.failure(i))\n".utf8))
    }

    /// Removes the record of the iteration in progress, once the run has no iteration in
    /// progress.
    func finish() {
        guard
        let (file, path): (FileHandle, String) = self.progress else {
            return
        }
        try? file.close()
        try? FileManager.default.removeItem(atPath: path)
    }

    /// The start of a failure message: the type, the iteration, and the seed that replays it.
    func failure(_ i: UInt64) -> String {
        """
        \(self.type), iteration \(i) from seed \(Self.hex(self.seed)) (replay with \
        DISTRIBUTED_ABI_FUZZ_SEED=\(Self.hex(self.seed(i))) DISTRIBUTED_ABI_FUZZ_ITERATIONS=1)
        """
    }

    /// The seed in hexadecimal with all its digits.
    private static func hex(_ seed: UInt64) -> String {
        let digits: String = .init(seed, radix: 16)
        return "0x\(String.init(repeating: "0", count: 16 - digits.count))\(digits)"
    }
}
