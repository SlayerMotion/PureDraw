// swift-tools-version: 5.9
// swiftformat:disable all
import PackageDescription

// PureDraw - Dependency-free, Swift-native 2D graphics engine.
//
// Hard rule for this repo: NO external SPM dependencies.

/// ---------- Dependencies ----------
let deps: [Package.Dependency] = [
    // Documentation tooling (build-time plugin only; not linked into the library).
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3"),
]

/// ---------- Products ----------
let allProducts: [Product] = {
    let pureDrawProduct = Product.singleTargetLibrary("PureDraw")
    let geometryProduct = Product.singleTargetLibrary("Geometry")
    let validationProduct = Product.singleTargetLibrary("Validation")
    let coreProduct = Product.singleTargetLibrary("Core")
    let renderersProduct = Product.singleTargetLibrary("Renderers")

    return [
        pureDrawProduct,
        geometryProduct,
        validationProduct,
        coreProduct,
        renderersProduct,
    ]
}()

/// ---------- Targets ----------
let targets: [Target] = {
    // ---------- Foundation Layer ----------
    let geometryTarget = Target.target(
        name: "Geometry",
        dependencies: ["Validation"],
        path: "Sources/Geometry"
    )
    let geometryTestsTarget = Target.testTarget(
        name: "GeometryTests",
        dependencies: ["Geometry"],
        path: "Tests/GeometryTests"
    )
    let validationTarget = Target.target(
        name: "Validation",
        path: "Sources/Validation"
    )
    let foundationTargets = [
        geometryTarget,
        geometryTestsTarget,
        validationTarget
    ]

    // ---------- Core Layer ----------
    let coreTarget = Target.target(
        name: "Core",
        dependencies: [
            "Geometry",
            "Validation"
        ],
        path: "Sources/Core"
    )
    let coreTestsTarget = Target.testTarget(
        name: "CoreTests",
        dependencies: [
            "Geometry",
            "Validation",
            "Core"
        ],
        path: "Tests/CoreTests"
    )
    let coreTargets = [
        coreTarget,
        coreTestsTarget
    ]

    // ---------- Infrastructure Layer (Renderers) ----------
    let renderersTarget = Target.target(
        name: "Renderers",
        dependencies: ["Core"],
        path: "Sources/Renderers"
    )
    let renderersTestsTarget = Target.testTarget(
        name: "RenderersTests",
        dependencies: [
            "Geometry",
            "Validation",
            "Core",
            "Renderers"
        ],
        path: "Tests/RenderersTests"
    )
    let rendererTargets = [
        renderersTarget,
        renderersTestsTarget
    ]

    // ---------- Front-Door Layer (Umbrella Target) ----------
    let pureDrawTarget = Target.target(
        name: "PureDraw",
        dependencies: [
            "Geometry",
            "Validation",
            "Core",
            "Renderers"
        ],
        path: "Sources/PureDraw"
    )
    let frontDoorTargets = [
        pureDrawTarget
    ]

    // ---------- Benchmarks (executable, not run by `swift test`) ----------
    let benchmarkTarget = Target.executableTarget(
        name: "puredraw-bench",
        dependencies: [
            "Geometry",
            "Core",
            "Renderers"
        ],
        path: "Benchmarks/puredraw-bench"
    )
    let benchmarkTargets = [
        benchmarkTarget
    ]

    return foundationTargets + coreTargets + rendererTargets + frontDoorTargets + benchmarkTargets
}()

let package = Package(
    name: "PureDraw",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: allProducts,
    dependencies: deps,
    targets: targets
)

/// Helper extension
extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}
