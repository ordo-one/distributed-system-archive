// swift-tools-version: 6.2
import PackageDescription

let tag: String = "__TAG__"
var url: String {
    let release: String = "https://github.com/ordo-one/internal-distributed-system/releases/download/\(tag)"
    #if os(macOS)
    return "\(release)/DistributedABI-macOS.xcframework.zip"
    #else
    return "\(release)/DistributedABI-Linux.xcframework.zip"
    #endif
}
var checksum: String {
    #if os(macOS)
    "__CHECKSUM_MACOS__"
    #else
    "__CHECKSUM_LINUX__"
    #endif
}

let package: Package = .init(
    name: "internal-distributed-system",
    products: [
        .library(name: "DistributedABI", targets: ["DistributedABI"])
    ],
    targets: [
        .binaryTarget(name: "DistributedABI", url: url, checksum: checksum),
    ]
)
