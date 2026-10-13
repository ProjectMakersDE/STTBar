// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "STTBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .executableTarget(
            name: "STTBar",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit"),
                           .product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/STTBar"),
        .testTarget(name: "STTBarTests", dependencies: ["STTBar"], path: "Tests/STTBarTests"),
    ]
)
