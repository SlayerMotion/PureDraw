// swift-tools-version: 6.0
import PackageDescription

// PureDraw - Dependency-free, Swift-native 2D graphics engine.
//
// Hard rule for this repo: NO external SPM dependencies.

/// ---------- Dependencies ----------
let deps: [Package.Dependency] = []

/// ---------- Products ----------
let allProducts: [Product] = {
    let pureDrawProduct = Product.singleTargetLibrary("PureDraw")
    let pureGeometryProduct = Product.singleTargetLibrary("PureGeometry")
    let pureValidationProduct = Product.singleTargetLibrary("PureValidation")
    let pureDrawCoreProduct = Product.singleTargetLibrary("PureDrawCore")
    let renderersProduct = Product.singleTargetLibrary("Renderers")

    return [
        pureDrawProduct,
        pureGeometryProduct,
        pureValidationProduct,
        pureDrawCoreProduct,
        renderersProduct,
    ]
}()

/// ---------- Targets ----------
let targets: [Target] = {
    // ---------- Foundation Layer ----------
    let pureGeometryTarget = Target.target(
        name: "PureGeometry",
        dependencies: ["PureValidation"],
        path: "Sources/PureGeometry",
    )
    let pureGeometryTestsTarget = Target.testTarget(
        name: "PureGeometryTests",
        dependencies: ["PureGeometry"],
        path: "Tests/PureGeometryTests",
    )
    let pureValidationTarget = Target.target(
        name: "PureValidation",
        path: "Sources/PureValidation",
    )
    let foundationTargets = [
        pureGeometryTarget,
        pureGeometryTestsTarget,
        pureValidationTarget,
    ]

    // ---------- Core Layer ----------
    let pureDrawCoreTarget = Target.target(
        name: "PureDrawCore",
        dependencies: [
            "PureGeometry",
            "PureValidation",
        ],
        path: "Sources/PureDrawCore",
    )
    let pureDrawCoreTestsTarget = Target.testTarget(
        name: "PureDrawCoreTests",
        dependencies: [
            "PureGeometry",
            "PureValidation",
            "PureDrawCore",
        ],
        path: "Tests/PureDrawCoreTests",
    )
    let coreTargets = [
        pureDrawCoreTarget,
        pureDrawCoreTestsTarget,
    ]

    // ---------- Infrastructure Layer (Renderers) ----------
    let renderersTarget = Target.target(
        name: "Renderers",
        dependencies: ["PureDrawCore"],
        path: "Sources/Renderers",
    )
    let renderersTestsTarget = Target.testTarget(
        name: "RenderersTests",
        dependencies: [
            "PureGeometry",
            "PureValidation",
            "PureDrawCore",
            "Renderers",
        ],
        path: "Tests/RenderersTests",
    )
    let rendererTargets = [
        renderersTarget,
        renderersTestsTarget,
    ]

    // ---------- Front-Door Layer (Umbrella Target) ----------
    let pureDrawTarget = Target.target(
        name: "PureDraw",
        dependencies: [
            "PureGeometry",
            "PureValidation",
            "PureDrawCore",
            "Renderers",
        ],
        path: "Sources/PureDraw",
    )
    let frontDoorTargets = [
        pureDrawTarget,
    ]

    return foundationTargets + coreTargets + rendererTargets + frontDoorTargets
}()

let package = Package(
    name: "PureDraw",
    products: allProducts,
    dependencies: deps,
    targets: targets,
)

/// Helper extension
extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}
