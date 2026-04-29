// swift-tools-version:6.0
import PackageDescription

let package: Package = .init(
    name: "distributed-system-benchmarks",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/dollup", from: "1.0.1"),
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.31.0"),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "DistributedSystemBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "OrdoDistributedABI", package: "internal-distributed-system"),
            ],
            path: "Benchmarks/DistributedSystemBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        ),
    ]
)
