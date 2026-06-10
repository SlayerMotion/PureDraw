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

### High-Level Roadmap Flow
```mermaid
flowchart TD
    classDef done fill:#34c759,stroke:#000,color:#fff
    classDef active fill:#007aff,stroke:#000,color:#fff

    E0["E0 (#1): Math Primitives"]:::done
    E1["E1 (#2): Path Construction"]:::done
    E2["E2 (#3): Graphic State"]:::done
    E3["E3 (#4): Rendering Bridge"]:::done
    
    Epic9["Epic #9: Bitmap Images"]:::active
    Epic13["Epic #13: Masking & Streams"]:::active
    Epic18["Epic #18: Typography"]:::active
    Epic22["Epic #22: Advanced PDF"]:::active

    E0 --> E1 --> E2 --> E3
    E3 --> Epic9 --> Epic13
    Epic9 --> Epic18
    Epic13 --> Epic22

    click E0 href "https://github.com/mihaelamj/PureDraw/issues/1" "E0"
    click E1 href "https://github.com/mihaelamj/PureDraw/issues/2" "E1"
    click E2 href "https://github.com/mihaelamj/PureDraw/issues/3" "E2"
    click E3 href "https://github.com/mihaelamj/PureDraw/issues/4" "E3"
    click Epic9 href "https://github.com/mihaelamj/PureDraw/issues/9" "Epic #9"
    click Epic13 href "https://github.com/mihaelamj/PureDraw/issues/13" "Epic #13"
    click Epic18 href "https://github.com/mihaelamj/PureDraw/issues/18" "Epic #18"
    click Epic22 href "https://github.com/mihaelamj/PureDraw/issues/22" "Epic #22"
```

### Epic #9: Bitmap Images & Rasterization Support
```mermaid
flowchart TD
    Epic9["Epic #9: Bitmap Images & Rasterization"]:::epic --> I10["#10: Raw Pixel Buffer Structure"]:::issue
    Epic9 --> I11["#11: Bitmap Context Renderer"]:::issue
    Epic9 --> I12["#12: Image Drawing on Context"]:::issue
    
    I10 --> I11
    I10 --> I12
    I11 --> I12

    classDef epic fill:#5856d6,stroke:#000,color:#fff,stroke-width:2px;
    classDef issue fill:#007aff,stroke:#000,color:#fff;
    click Epic9 href "https://github.com/mihaelamj/PureDraw/issues/9" "Epic #9"
    click I10 href "https://github.com/mihaelamj/PureDraw/issues/10" "Issue #10"
    click I11 href "https://github.com/mihaelamj/PureDraw/issues/11" "Issue #11"
    click I12 href "https://github.com/mihaelamj/PureDraw/issues/12" "Issue #12"
```

### Epic #13: Image Masking, Caching & Data Streams
```mermaid
flowchart TD
    Epic13["Epic #13: Masking, Caching & Streams"]:::epic --> I14["#14: Stencil & Chroma Masking"]:::issue
    Epic13 --> I15["#15: CGLayer Caching"]:::issue
    Epic13 --> I16["#16: Data Providers & Consumers"]:::issue
    Epic13 --> I17["#17: Image I/O Metadata"]:::issue
    
    I16 --> I17

    classDef epic fill:#5856d6,stroke:#000,color:#fff,stroke-width:2px;
    classDef issue fill:#007aff,stroke:#000,color:#fff;
    click Epic13 href "https://github.com/mihaelamj/PureDraw/issues/13" "Epic #13"
    click I14 href "https://github.com/mihaelamj/PureDraw/issues/14" "Issue #14"
    click I15 href "https://github.com/mihaelamj/PureDraw/issues/15" "Issue #15"
    click I16 href "https://github.com/mihaelamj/PureDraw/issues/16" "Issue #16"
    click I17 href "https://github.com/mihaelamj/PureDraw/issues/17" "Issue #17"
```

### Epic #18: Typography and Text Layout Engine
```mermaid
flowchart TD
    Epic18["Epic #18: Typography & Text Layout"]:::epic --> I19["#19: Font File Parser & Glyphs"]:::issue
    Epic18 --> I20["#20: Text State Stack & Matrix"]:::issue
    Epic18 --> I21["#21: Text Showing Context Operations"]:::issue
    
    I19 --> I21
    I20 --> I21

    classDef epic fill:#5856d6,stroke:#000,color:#fff,stroke-width:2px;
    classDef issue fill:#007aff,stroke:#000,color:#fff;
    click Epic18 href "https://github.com/mihaelamj/PureDraw/issues/18" "Epic #18"
    click I19 href "https://github.com/mihaelamj/PureDraw/issues/19" "Issue #19"
    click I20 href "https://github.com/mihaelamj/PureDraw/issues/20" "Issue #20"
    click I21 href "https://github.com/mihaelamj/PureDraw/issues/21" "Issue #21"
```

### Epic #22: Advanced PDF Systems
```mermaid
flowchart TD
    Epic22["Epic #22: Advanced PDF Systems"]:::epic --> I23["#23: PDF Outlines & Hyperlinks"]:::issue
    Epic22 --> I24["#24: PDF Page Boxes & Transforms"]:::issue
    Epic22 --> I25["#25: Low-Level PDF Scanning"]:::issue
    Epic22 --> I26["#26: PDF Encryption & Permissions"]:::issue
    
    I23 --> I24
    I24 --> I25
    I25 --> I26

    classDef epic fill:#5856d6,stroke:#000,color:#fff,stroke-width:2px;
    classDef issue fill:#007aff,stroke:#000,color:#fff;
    click Epic22 href "https://github.com/mihaelamj/PureDraw/issues/22" "Epic #22"
    click I23 href "https://github.com/mihaelamj/PureDraw/issues/23" "Issue #23"
    click I24 href "https://github.com/mihaelamj/PureDraw/issues/24" "Issue #24"
    click I25 href "https://github.com/mihaelamj/PureDraw/issues/25" "Issue #25"
    click I26 href "https://github.com/mihaelamj/PureDraw/issues/26" "Issue #26"
```

---

## Community & Documentation

* [CONTRIBUTING.md](CONTRIBUTING.md) : How to contribute and code conventions.
* [SECURITY.md](SECURITY.md) : Vulnerability reporting policy.
* [SUPPORT.md](SUPPORT.md) : How to get help or ask questions.
* [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) : Community guidelines.
* [AGENTS.md](AGENTS.md) : AI agent instructions.
* [LICENSE](LICENSE) : Licensed under the MIT License.
