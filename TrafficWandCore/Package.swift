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
            // Fixtures are loaded from disk via `#filePath` (see FixtureLoader),
            // not bundled as SPM resources, so exclude them from the build to
            // silence the unhandled-files warning.
            exclude: ["Fixtures"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
