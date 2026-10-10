// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenOne",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OpenOne", targets: ["OpenOne"])],
    targets: [
        .target(name: "OneCore"),
        .executableTarget(name: "OpenOne", dependencies: ["OneCore"], resources: [.process("Assets")]),
        .testTarget(name: "OneCoreTests", dependencies: ["OneCore"])
    ]
)
