// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pyaww",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PyawwCore", targets: ["PyawwCore"]),
        .executable(name: "PyawwApp", targets: ["PyawwApp"]),
        .executable(name: "pyaww-cli", targets: ["PyawwCLI"]),
    ],
    targets: [
        .target(
            name: "PyawwCore",
            resources: [.copy("Resources/lexicons.json")]),
        .executableTarget(
            name: "PyawwApp", dependencies: ["PyawwCore"], path: "App",
            exclude: ["Info.plist"]),
        .executableTarget(name: "PyawwCLI", dependencies: ["PyawwCore"]),
        .testTarget(name: "PyawwCoreTests", dependencies: ["PyawwCore"]),
        .testTarget(name: "PyawwAppTests", dependencies: ["PyawwApp", "PyawwCore"]),
    ]
)
