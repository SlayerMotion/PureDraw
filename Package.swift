// swift-tools-version: 6.0
import PackageDescription

// PureDraw - Dependency-free, Swift-native 2D graphics engine.
//
// Hard rule for this repo: NO external SPM dependencies.

let package = Package(
    name: "PureDraw",
    products: [
        .library(name: "PureDraw", targets: ["PureDraw"]),
    ],
    targets: [
        .target(
            name: "PureDraw",
            path: "Sources"
        ),
        .testTarget(
            name: "PureDrawTests",
            dependencies: ["PureDraw"],
            path: "Tests"
        ),
    ]
)
