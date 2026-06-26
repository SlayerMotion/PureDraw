// swift-tools-version: 5.9
// swiftformat:disable all
import PackageDescription

// CGS - Swift binding to the private CoreGraphics Services / SkyLight window-server SPI.
//
// This package is deliberately kept OUTSIDE the PureDraw dependency hierarchy
// (Validation -> Geometry -> Core -> Renderers -> PureDraw). PureDraw is a
// portable, dependency-free Quartz 2D engine; this is the opposite: macOS-only,
// Foundation-using, and bound to undocumented WindowServer entry points. Nothing
// in the core may depend on it. See README.md.
//
// Symbols are declared with @_silgen_name and resolved at runtime through dyld
// (`-undefined dynamic_lookup`), so no private framework needs to be present in
// the SDK at link time. They are provided by CoreGraphics / SkyLight, both of
// which are already loaded in any GUI session.

let package = Package(
    name: "CGS",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "CGS", targets: ["CGS"]),
    ],
    targets: [
        .target(
            name: "CGS",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-undefined",
                    "-Xlinker", "dynamic_lookup",
                ]),
            ]
        ),
    ]
)
