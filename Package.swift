// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IrisGate",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "IrisGate", targets: ["IrisGate"])],
    targets: [
        .target(name: "IrisGateCore"),
        .executableTarget(name: "IrisGate", dependencies: ["IrisGateCore"]),
        .testTarget(name: "IrisGateCoreTests", dependencies: ["IrisGateCore"])
    ],
    swiftLanguageModes: [.v5]
)
