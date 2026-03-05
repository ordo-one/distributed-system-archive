// swift-tools-version: 6.2
import PackageDescription
import class Foundation.ProcessInfo

let package: Package = .init(
    name: "internal-distributed-system",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "OrdoDistributedABI",
            type: .dynamic,
            targets: ["DistributedABI"]
        ),
    ],
    targets: [
        .target(
            name: "DistributedABI",
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution", "-emit-module-interface"]),
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
