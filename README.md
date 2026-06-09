# PureDraw

[![Style and namespacing](https://github.com/mihaelamj/PureDraw/actions/workflows/style.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/style.yml)
[![Swift macOS](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-macos.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-macos.yml)
[![Swift Linux](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-linux.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-linux.yml)
[![Swift Windows](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-windows.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-windows.yml)
[![Swift WASM](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-wasm.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-wasm.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)

PureDraw is a dependency-free, Swift-native 2D vector graphics engine.

It provides a "Virtual PostScript Machine" API compatible with CoreGraphics (Quartz) and the HTML5 Canvas. The library is highly portable and follows a strict design:
- **Zero external dependencies** (no SPM dependencies, no package drift)
- **Zero bundled C/C++ sources** (pure Swift)
- **No Foundation requirements** in the core library target
- **Cross-platform build gates** for macOS, Linux, Windows, and WebAssembly (WASI)

It is a sibling project to [PureXML](https://github.com/mihaelamj/PureXML) and [PureYAML](https://github.com/mihaelamj/PureYAML).

---

## Preview

Here is a 3D perspective scene generated entirely by PureDraw (available in the test suite), showcasing linear gradients, 3D grids, perspective-distorted 2D badges, crumpled paper deformation, multiply blend modes, and drop shadows rendered to a vector PDF:

![PureDraw 3D perspective scene preview](3d_transform_scene_preview.png)

---

## Core Features

### 1. Advanced Transformations
* **Affine Transforms:** Full 3x3 matrix math (`AffineTransform`) for scaling, rotation, translation, and skewing.
* **Projective Transforms:** Homography/quadrilateral mapping (`ProjectiveTransform.rectToQuad`) to map 2D coordinates into arbitrary 3D perspective quads.

### 2. Path Deformations
* **Path Subdivision:** Fine-grained subdivision (`path.subdivided(maxSegmentLength:)`) to break straight lines and curves into high-resolution micro-segments.
* **Non-Linear Deformers:** Dynamic vertex displacement (e.g. `CrumpleDeformer`) to simulate physical processes like paper crushing, pinching, and wrinkling.

### 3. State-Based Graphics Context
* Standard vector drawing API with `move(to:)`, `addLine(to:)`, `addCurve(to:)`, `addEllipse(in:)`, and `addRoundedRect(in:)`.
* Graphics state stack via `saveGState()` and `restoreGState()`.
* Native support for **clipping paths**, **linear gradients**, and **vector drop shadows**.
* Compositing and transparency controls, including **blend modes** (like `multiply`).

### 4. Vector Export Engines
* **PDFRenderer:** Compiles graphics contexts to compact, standard PDF documents.
* **SVGRenderer:** Exports to scalable vector graphics XML.
* **PostScriptRenderer:** Exports standard EPS (Encapsulated PostScript) vector code.
* **CoreGraphicsRenderer:** Bridges directly to Apple's native CoreGraphics framework.

### 5. Declarative Validation Framework
* Follows the **OpenAPIKit validation idiom** by Matt Polzin.
* Validation rules are composable values (`Validation<Subject>`), not imperative `if-else` trees.
* Validates geometry finiteness, clipping boundaries, color parameters, and graphic state nesting.

---

## Code Example

```swift
import PureDraw

// 1. Create a Graphics Context
var context = GraphicsContext()

// 2. Configure Graphic State
context.saveGState()
context.setFillColor(Color(red: 0.1, green: 0.7, blue: 0.9, alpha: 0.8))
context.setShadow(offset: Point(x: 4, y: 4), blur: 5.0, color: Color(red: 0, green: 0, blue: 0, alpha: 0.4))

// 3. Define a Homography (Projective) Transform
let sourceRect = Rect(x: 0, y: 0, width: 100, height: 100)
let targetQuad = (
    p0: Point(x: 20, y: 10),  // Top-left
    p1: Point(x: 120, y: 5),  // Top-right
    p2: Point(x: 110, y: 95), // Bottom-right
    p3: Point(x: 10, y: 80)   // Bottom-left
)
let transform = ProjectiveTransform.rectToQuad(
    sourceRect,
    p0: targetQuad.p0,
    p1: targetQuad.p1,
    p2: targetQuad.p2,
    p3: targetQuad.p3
)

// 4. Construct and Transform Geometry
var path = Path()
path.addRoundedRect(in: sourceRect, cornerWidth: 8, cornerHeight: 8)
let transformedPath = path.applying(transform)

context.addPath(transformedPath)
context.fillPath()
context.restoreGState()

// 5. Render to Vector PDF
let pdfData = try PDFRenderer(width: 200, height: 200).render(context)
```

---

## Build and Test

PureDraw uses standard SwiftPM commands:

```bash
# Build the library and test targets
swift build

# Run the test suite (generates test outputs)
swift test

# Run code formatter
swiftformat . --config .swiftformat

# Run code linter
swiftlint --config .swiftlint.yml --strict
```

Alternatively, you can run all local verification gates with:
```bash
bash scripts/check-all.sh
```

---

## Roadmap

```mermaid
flowchart TB
classDef done fill:#34c759,stroke:#000,color:#fff
classDef active fill:#007aff,stroke:#000,color:#fff
classDef review fill:#ff9500,stroke:#000,color:#fff
classDef todo fill:#8e8e93,stroke:#000,color:#fff
classDef blocked fill:#ff3b30,stroke:#000,color:#fff

E0["E0 (#1): Mathematical Primitives"]:::done
E1["E1 (#2): Path Construction"]:::done
E2["E2 (#3): Graphic State Management"]:::done
E3["E3 (#4): Rendering Bridge"]:::done

E0 --> E1
E1 --> E2
E2 --> E3
```

---

## Community & Documentation

* [CONTRIBUTING.md](CONTRIBUTING.md) : How to contribute and code conventions.
* [SECURITY.md](SECURITY.md) : Vulnerability reporting policy.
* [SUPPORT.md](SUPPORT.md) : How to get help or ask questions.
* [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) : Community guidelines.
* [AGENTS.md](AGENTS.md) : AI agent instructions.
* [LICENSE](LICENSE) : Licensed under the MIT License.
