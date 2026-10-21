// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "RelayCore", targets: ["RelayCore"])]
var targets: [Target] = [
    .target(name: "RelayCore"),
    .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"])
]
#if os(macOS)
products.append(.executable(name: "Blink", targets: ["RelayApp"]))
targets.append(.executableTarget(name: "RelayApp", dependencies: ["RelayCore"]))
#endif

let package = Package(name: "Blink", platforms: [.macOS(.v13)], products: products, targets: targets)
