# Master Catalog of CoreGraphics & Quartz 2D Feature Gaps

This document presents the consolidated, comprehensive list of all missing features and architecture gaps in `PureDraw` compared to the complete Quartz 2D / CoreGraphics specifications detailed in:
- *Programming with Quartz (2005)* (Chapters 1–14)
- *Quartz 2D Graphics for Mac OS X® Developers* (R. Scott Thompson, 2006)
- *Big Nerd Ranch Core Graphics Guide* (Parts 1–4)

---

## 1. Summary Status Matrix

| Feature / System | Source Reference | Status | PureDraw Reference / Files | Gap Details | Target Phase |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Graphics State Variables** | *Quartz* Ch. 4, 11<br>*Thompson* Ch. 4, 8, 11 | **Missing** | [GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift) | Missing `interpolationQuality`, `renderingIntent`, `shouldAntialias`, `shouldSmoothFonts`, and `shouldSubpixelPositionFonts`. | Phase 1.3 |
| **Typography & Text Layout** | *Quartz* Ch. 11–12<br>*Thompson* Ch. 11 | **Missing** | *None* | No font file loading, glyph registration, text matrix CTM mapping, or text clipping. | Phase 4 |
| **Bitmap Images & Contexts** | *Quartz* Ch. 10<br>*Thompson* Ch. 8, 12 | **Missing** | *None* | No raw pixel buffers, offscreen raster contexts, or float/premultiplied alpha layout configs. | Phase 2.1 |
| **Cache Layers (`CGLayer`)** | *Thompson* Ch. 12<br>*Quartz* Ch. 12 | **Missing** | *None* | No GPU/VRAM optimized cache layer representation for repeated drawings. | Phase 2.3 |
| **Image & Stencil Masking** | *Quartz* Ch. 10 | **Missing** | *None* | No alpha/luminance image masking or color-range chroma-key filtering. | Phase 2.2 |
| **Image I/O Metadata** | *Thompson* Ch. 9<br>*Quartz* Ch. 9 | **Missing** | *None* | No container-level metadata reading/writing (EXIF, GPS, IPTC) decoupled from pixel data. | Phase 2.4 |
| **Data Streams (`CGDataProvider`)** | *Quartz* Ch. 8<br>*Thompson* Ch. 8 | **Missing** | *None* | No `CGDataProvider` / `CGDataConsumer` stream abstractions to decouple file/memory operations. | Phase 2.5 |
| **Path Hit Detection** | *Quartz* Ch. 6 | **Missing** | [Path.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/Path.swift) | No hit-testing containment checks (`CGContextPathContainsPoint` / `contains(point:rule:)`) for interactive shapes. | Phase 1.4 |
| **Tiling Patterns** | *Quartz* Ch. 7<br>*Thompson* Ch. 13 | **Missing** | *None* | No colored or uncolored template repeating cell patterns. | Phase 3.1 |
| **Custom Shading** | *Quartz* Ch. 8<br>*Thompson* Ch. 13 | **Partially Implemented** | [Gradient.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/Gradient.swift) | Axial/radial gradients are supported, but functional shading math evaluated per coordinate is missing. | Phase 3.2 |
| **Advanced Color Spaces** | *Quartz* Ch. 5 | **Partially Implemented** | [Color.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/Color.swift) | CMYK and Gray spaces are supported, but Calibrated spaces (sRGB/Lab) and ICC profiles are missing. | Phase 1.2 |
| **PDF Outlines & Parsing** | *Quartz* Ch. 12 | **Partially Implemented** | [PDFRenderer.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Renderers/PDFRenderer.swift) | PDF writing works. Outlines, hyperlinks, and document annotations are missing. | Phase 5.1 |
| **PDF Boxes & Transforms** | *Quartz* Ch. 12<br>*Thompson* Ch. 14 | **Missing** | [PDFRenderer.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Renderers/PDFRenderer.swift) | Page boundary box metrics (CropBox, BleedBox, TrimBox, ArtBox) and auto-orientation matrices are missing. | Phase 5.3 |
| **PDF Content Scanning** | *Quartz* Ch. 14<br>*Thompson* Ch. 14 | **Missing** | *None* | No `CGPDFScanner` pipeline to pop operand stack parameters and invoke operator callbacks. | Phase 5.2 |
| **PDF Document Encryption** | *Quartz* Ch. 12 | **Missing** | *None* | No support for password-based decryption (`CGPDFDocumentUnlockWithPassword`) or print/copy permission checking. | Phase 5.4 |
| **Core Image Filters** | *Thompson* Ch. 10 | **Out of Scope** | *None* | GPU-accelerated filter graphs (`CIFilter`/`CIContext`). | *None* |
| **OS Events & Printing** | *Quartz* Ch. 13–14 | **Out of Scope** | *None* | Host OS window loops, print layout dialogs, and low-level mouse/keyboard event taps. | *None* |

---

## 2. Detailed Gap Analyses

### 2.1 Graphics State Variables
* **Origin**: *Programming with Quartz* Chapter 4 (Context Parameters); *Thompson* Chapter 4 (Graphics State).
* **Gap Description**: Multiple CoreGraphics state properties are missing from the painter state stack in [GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift).
* **Core Requirements**:
  1. **`interpolationQuality`**: An enum (`.none`, `.low`, `.medium`, `.high`) indicating the interpolation quality used for scaling/rotating images.
  2. **`renderingIntent`**: Color matching parameters during space conversions.
  3. **`shouldAntialias` / `allowsAntialiasing`**: Boolean toggles to disable vector anti-aliasing for custom rendering efficiency.
  4. **Font Smoothing Flags**: `shouldSmoothFonts`, `allowsFontSmoothing`, and `shouldSubpixelPositionFonts` to configure glyph rasterization details.
* **Target Phase**: **Phase 1.3**

### 2.2 Typography and Text Layout Engine
* **Origin**: *Programming with Quartz* Chapters 11–12; *Thompson* Chapter 11.
* **Gap Description**: `PureDraw` has no font descriptor loading, glyph representation, or text layouts.
* **Core Requirements**:
  1. **Font Loaders**: TrueType/OpenType font table parser to extract vector path glyphs.
  2. **Text State Variables**: Set text matrix CTM (`CGContextSetTextMatrix`), size, rendering mode, and font inside the context.
  3. **Text Operations**: Context drawing functions like `showText(_:at:)` and `showGlyphs(_:at:)`.
* **Target Phase**: **Phase 4**

### 2.3 Bitmap Images and Rasterization
* **Origin**: *Programming with Quartz* Chapter 10; *Thompson* Chapters 8, 12.
* **Gap Description**: Missing raw image models, offscreen buffer bitmap contexts, and raw pixel writing.
* **Core Requirements**:
  1. **Image Type**: Raw pixel matrix buffer (RGBA, Grayscale, etc.).
  2. **Bitmap Context**: A graphics context that rasterizes path drawing commands into a raw pixel memory buffer instead of vector commands.
  3. **Pixel Layout Settings**: Premultiplied alpha support, floating-point component values, and alpha-only image formats.
* **Target Phase**: **Phase 2.1**

### 2.4 Caching Layers (`CGLayer`)
* **Origin**: *Thompson* Chapter 12 (Drawing Offscreen); *Programming with Quartz* Chapter 12.
* **Gap Description**: No hardware-accelerated drawing cache layer.
* **Core Requirements**:
  1. **Caching Element**: A cached layout object associated with a target context, inheriting its scale, color space, and characteristics.
  2. **Fast Compositing**: Replaying the recorded command stream as a pre-rendered texture directly to the target context without CPU overhead.
* **Target Phase**: **Phase 2.3**

### 2.5 Image and Stencil Masking
* **Origin**: *Programming with Quartz* Chapter 10.
* **Gap Description**: Only path-based clipping (`clipPath`) is supported.
* **Core Requirements**:
  1. **Stencil Masks**: Masking graphics where visibility is determined by the alpha or luminance values of a bitmap image.
  2. **Chroma-Key Masking**: Specifying range boundaries of color channels to mask out background backdrops of drawn images.
* **Target Phase**: **Phase 2.2**

### 2.6 Image I/O Metadata
* **Origin**: *Thompson* Chapter 9 (Importing and Exporting Images).
* **Gap Description**: No capability to parse or write EXIF, GPS, IPTC, or system metadata streams.
* **Core Requirements**:
  1. **Image Source**: Loading metadata dictionaries from file headers without full pixel decode.
  2. **Image Destination**: Writing container tags when compiling final image packages.
* **Target Phase**: **Phase 2.4**

### 2.7 Data Providers & Consumers (`CGDataProvider`)
* **Origin**: *Programming with Quartz* Chapter 8; *Thompson* Chapter 8.
* **Gap Description**: No generic data stream abstraction layer.
* **Core Requirements**:
  1. **Data Provider**: Stream reader structure encapsulating file handles, web URLs, or memory blocks.
  2. **Data Consumer**: Stream writer structure encapsulating output files or dynamic memory allocations.
* **Target Phase**: **Phase 2.5**

### 2.8 Path Hit Detection
* **Origin**: *Programming with Quartz* Chapter 6 (Geometric operations).
* **Gap Description**: Currently, paths only store lines and curve elements, offering no way to query if a point falls inside their boundaries.
* **Core Requirements**:
  1. **Winding Containment**: Geometric algorithm to check if a specific `Point` is contained within a subpath using the Nonzero Winding or Even-Odd rule.
  2. **Context Helper**: `context.pathContains(point: Point, using: FillRule)` equivalent to `CGContextPathContainsPoint`.
* **Target Phase**: **Phase 1.4**

### 2.9 Repeating Pattern Fills (Tiling Patterns)
* **Origin**: *Programming with Quartz* Chapter 7; *Thompson* Chapter 13.
* **Gap Description**: No repeating vector cell fills (for grids, stripes, hatches) inside stroke/fill paths.
* **Core Requirements**:
  1. **Pattern Space**: Coordinate systems mapped to repeating cell matrices.
  2. **Colored Patterns**: Fills using cell graphics with fixed colors.
  3. **Uncolored Patterns**: Fills using template graphics acting as masks inheriting the context's current fill/stroke color.
* **Target Phase**: **Phase 3.1**

### 2.10 Custom Mathematical Shading (CGFunction / CGShading)
* **Origin**: *Programming with Quartz* Chapter 8; *Thompson* Chapter 13.
* **Gap Description**: Linear/radial stops are supported, but functional shading is missing.
* **Core Requirements**:
  1. **Function Evaluators**: An algebraic or programmatic coordinate function $f(x, y) = \text{Color}$ evaluated per pixel.
  2. **Renderer Bridge**: Vector output support (e.g. PDF shading dictionary definitions).
* **Target Phase**: **Phase 3.2**

### 2.11 Calibrated Color Spaces & ICC Profiles
* **Origin**: *Programming with Quartz* Chapter 5.
* **Gap Description**: RGB, CMYK, and Gray color components are locally supported, but device-independent calibrated spaces are missing.
* **Core Requirements**:
  1. **Calibrated Color Spaces**: Reference spaces (like sRGB, Adobe RGB, Lab) defining absolute values.
  2. **ICC Profile Injection**: Attaching raw ColorSync ICC profile dictionaries to PDF and PostScript outputs.
* **Target Phase**: **Phase 1.2 (Extended)**

### 2.12 PDF Outlines & Page Boundary Boxes
* **Origin**: *Programming with Quartz* Chapter 12; *Thompson* Chapter 14.
* **Gap Description**: PDF renderer only exports raw drawing content into a standard `/MediaBox`.
* **Core Requirements**:
  1. **Page Boxes**: Support specifying `CropBox`, `BleedBox`, `TrimBox`, and `ArtBox` coordinates for print margins.
  2. **Drawing Transform**: Function equivalent to `CGPDFPageGetDrawingTransform` that calculates layout CTMs to fit and orient page rectangles into a view.
  3. **Interactive Trees**: Tree outlines (TOC) and coordinates-based hyperlink hotspots.
* **Target Phase**: **Phase 5.1 & Phase 5.3**

### 2.13 PDF Content Scanning
* **Origin**: *Programming with Quartz* Chapter 14; *Thompson* Chapter 14.
* **Gap Description**: No mechanism to parse or deconstruct existing PDF vector content streams.
* **Core Requirements**:
  1. **PDF Content Scanner**: Opaque scanner structure (`CGPDFScannerRef`) mapping registration callback routines to PDF operator characters.
  2. **Operand Stack**: Support popping variables (`CGPDFScannerPopName`, `CGPDFScannerPopStream`) off the PDF evaluation stack.
* **Target Phase**: **Phase 5.2**

### 2.14 PDF Document Encryption & Permissions
* **Origin**: *Programming with Quartz* Chapter 12 (Security model).
* **Gap Description**: No capability to lock/unlock documents or check security flags.
* **Core Requirements**:
  1. **Decryption Handler**: `CGPDFDocumentUnlockWithPassword` using user or owner password keys (40 to 128 bit keys).
  2. **Permission Query**: `CGPDFDocumentAllowsPrinting` and `CGPDFDocumentAllowsCopying` to respect document copyright settings.
* **Target Phase**: **Phase 5.4**
