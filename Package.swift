// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pyaww",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PyawwCore", targets: ["PyawwCore"]),
        .executable(name: "pyaww-cli", targets: ["PyawwCLI"]),
    ],
    targets: [
        .target(name: "PyawwCore"),
        .executableTarget(name: "PyawwCLI", dependencies: ["PyawwCore"]),
        .testTarget(name: "PyawwCoreTests", dependencies: ["PyawwCore"]),
    ]
)
