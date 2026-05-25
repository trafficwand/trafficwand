// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrafficWandCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TrafficWandCore",
            targets: ["TrafficWandCore"]
        )
    ],
    targets: [
        .target(
            name: "TrafficWandCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TrafficWandCoreTests",
            dependencies: ["TrafficWandCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
