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
    let svgRendererProduct = Product.singleTargetLibrary("SVGRenderer")
    let canvasRendererProduct = Product.singleTargetLibrary("CanvasRenderer")
    let pdfRendererProduct = Product.singleTargetLibrary("PDFRenderer")
    let postScriptRendererProduct = Product.singleTargetLibrary("PostScriptRenderer")

    let baseProducts = [
        pureDrawProduct,
        pureGeometryProduct,
        pureValidationProduct,
        pureDrawCoreProduct,
        svgRendererProduct,
        canvasRendererProduct,
        pdfRendererProduct,
        postScriptRendererProduct,
    ]

    #if os(iOS) || os(macOS)
        let coreGraphicsRendererProduct = Product.singleTargetLibrary("CoreGraphicsRenderer")
        let appleOnlyProducts = [
            coreGraphicsRendererProduct,
        ]
    #else
        let appleOnlyProducts: [Product] = []
    #endif

    return baseProducts + appleOnlyProducts
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
    let svgRendererTarget = Target.target(
        name: "SVGRenderer",
        dependencies: ["PureDrawCore"],
        path: "Sources/SVGRenderer",
    )
    let canvasRendererTarget = Target.target(
        name: "CanvasRenderer",
        dependencies: ["PureDrawCore"],
        path: "Sources/CanvasRenderer",
    )
    let pdfRendererTarget = Target.target(
        name: "PDFRenderer",
        dependencies: ["PureDrawCore"],
        path: "Sources/PDFRenderer",
    )
    let postScriptRendererTarget = Target.target(
        name: "PostScriptRenderer",
        dependencies: ["PureDrawCore"],
        path: "Sources/PostScriptRenderer",
    )

    let baseRenderers = [
        svgRendererTarget,
        canvasRendererTarget,
        pdfRendererTarget,
        postScriptRendererTarget,
    ]

    #if os(iOS) || os(macOS)
        let coreGraphicsRendererTarget = Target.target(
            name: "CoreGraphicsRenderer",
            dependencies: ["PureDrawCore"],
            path: "Sources/CoreGraphicsRenderer",
        )
        let appleOnlyRenderers = [
            coreGraphicsRendererTarget,
        ]
    #else
        let appleOnlyRenderers: [Target] = []
    #endif

    // ---------- Unified Renderer Tests ----------
    let rendererTestsTarget = Target.testTarget(
        name: "RendererTests",
        dependencies: {
            var deps: [Target.Dependency] = [
                "PureGeometry",
                "PureValidation",
                "PureDrawCore",
                "SVGRenderer",
                "CanvasRenderer",
                "PDFRenderer",
                "PostScriptRenderer",
            ]
            #if os(iOS) || os(macOS)
                deps.append("CoreGraphicsRenderer")
            #endif
            return deps
        }(),
        path: "Tests/RendererTests",
    )

    let rendererTargets = baseRenderers + appleOnlyRenderers + [rendererTestsTarget]

    // ---------- Front-Door Layer (Umbrella Target) ----------
    let pureDrawTarget = Target.target(
        name: "PureDraw",
        dependencies: {
            var deps: [Target.Dependency] = [
                "PureGeometry",
                "PureValidation",
                "PureDrawCore",
                "SVGRenderer",
                "CanvasRenderer",
                "PDFRenderer",
                "PostScriptRenderer",
            ]
            #if os(iOS) || os(macOS)
                deps.append("CoreGraphicsRenderer")
            #endif
            return deps
        }(),
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
