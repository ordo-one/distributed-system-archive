// swift-tools-version: 6.3
import PackageDescription

let package: Package = .init(
    name: "distributed-system-benchmarks",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/dollup", from: "1.0.1"),
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.31.0"),
        .package(name: "internal-distributed-system", path: ".."),
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
