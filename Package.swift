// swift-tools-version: 6.3
import PackageDescription
import class Foundation.ProcessInfo

let package: Package = .init(
    name: "distributed-system",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "OrdoDistributedABI",
            type: .dynamic,
            targets: ["DistributedABI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/dollup", from: "1.0.1"),
    ],
    targets: [
        .target(
            name: "DistributedABI",
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
                .strictMemorySafety(),
                .unsafeFlags(["-enable-library-evolution", "-emit-module-interface"]),
            ]
        ),
        .testTarget(
            name: "DistributedABITests",
            dependencies: [
                .target(name: "DistributedABI"),
            ]
        ),
    ]
)
package.targets = package.targets.map {
    switch $0.type {
    case .plugin: return $0
    case .binary: return $0
    default: break
    }
    {
        var settings: [SwiftSetting] = $0 ?? []

        settings.append(.enableUpcomingFeature("ExistentialAny"))
        // This would evaluate to true in CI, but not in normal local development
        if ProcessInfo.processInfo.environment["BUILD_WARNINGS_AS_ERRORS"] == "true" {
            settings.append(.treatWarning("ExistentialAny", as: .error))
            settings.append(.treatWarning("MutableGlobalVariable", as: .error))
        }

        $0 = settings
    } (&$0.swiftSettings)
    return $0
}
