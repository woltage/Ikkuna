// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "IkkunaCore", targets: ["IkkunaCore"])]
var targets: [Target] = [
    .target(name: "IkkunaCore"),
    .testTarget(name: "IkkunaCoreTests", dependencies: ["IkkunaCore"])
]
#if os(macOS)
products.append(.executable(name: "Ikkuna", targets: ["Ikkuna"]))
targets.append(.executableTarget(name: "Ikkuna", dependencies: ["IkkunaCore"]))
#endif
let package = Package(name: "Ikkuna", platforms: [.macOS(.v13)], products: products, targets: targets)
