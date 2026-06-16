// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "STTBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "STTBar", path: "Sources/STTBar"),
        .testTarget(name: "STTBarTests", dependencies: ["STTBar"], path: "Tests/STTBarTests"),
    ]
)
