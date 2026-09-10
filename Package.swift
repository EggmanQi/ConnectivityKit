// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "ConnectivityKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "ConnectivityCore", targets: ["ConnectivityCore"]),
        .library(name: "ConnectivityUI", targets: ["ConnectivityUI"]),
        .library(name: "ConnectivityDebugUI", targets: ["ConnectivityDebugUI"])
    ],
    targets: [
        .target(
            name: "ConnectivityCore",
            path: "Sources/ConnectivityCore"
        ),
        .target(
            name: "ConnectivityUI",
            dependencies: ["ConnectivityCore"],
            path: "Sources/ConnectivityUI",
            resources: [.process("Resources")]
        ),
        .target(
            name: "ConnectivityDebugUI",
            dependencies: ["ConnectivityCore", "ConnectivityUI"],
            path: "Sources/ConnectivityDebugUI"
        )
    ]
)
