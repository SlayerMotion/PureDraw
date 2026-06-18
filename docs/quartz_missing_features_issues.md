# GitHub Issue Templates for CoreGraphics/Quartz 2D Gaps

This document defines ready-to-file GitHub issues to address all missing features and architectural gaps in `PureDraw`, structured by parent Epics and child Issues.

---

## 1. Epic: Bitmap Images and Rasterization Support
**Epic Title:** `epic: implement bitmap images and offscreen rasterization`  
**Labels:** `epic`, `enhancement`

### Description
Introduce a native structure representing raw raster pixel data (RGBA) and a bitmap graphics context to render paths onto pixel memory buffers.

```mermaid
flowchart TB
    classDef done    fill:#34C759,color:#FFFFFF
    classDef active  fill:#007AFF,color:#FFFFFF
    classDef review  fill:#30B0C7,color:#FFFFFF
    classDef next    fill:#5856D6,color:#FFFFFF
    classDef partial fill:#FF9500,color:#FFFFFF
    classDef todo    fill:#8E8E93,color:#FFFFFF

    Epic9["Epic #9: Bitmap Images & Rasterization"]:::next --> I10["#10: Raw Pixel Buffer Structure"]:::todo --> I11["#11: Bitmap Context Renderer"]:::todo --> I12["#12: Image Drawing on Context"]:::todo

    click Epic9 href "https://github.com/SlayerMotion/PureDraw/issues/9" "Epic #9"
    click I10 href "https://github.com/SlayerMotion/PureDraw/issues/10" "Issue #10"
    click I11 href "https://github.com/SlayerMotion/PureDraw/issues/11" "Issue #11"
    click I12 href "https://github.com/SlayerMotion/PureDraw/issues/12" "Issue #12"
```

### Child Issues

#### Issue 1a: `feat: implement raw pixel image buffer structure (CGImage equivalent)`
* **Description**: Create a raw pixel buffer structure that holds layout configuration (e.g., RGBA8888, Grayscale, premultiplied alpha channels, or float components).
* **Affected Files**: `Sources/Core/Image.swift` (New file)

#### Issue 1b: `feat: implement bitmap context graphics renderer (CGBitmapContext equivalent)`
* **Description**: Implement a graphics context renderer that rasterizes path drawing commands, strokes, fills, and transparencies into a raw pixel memory buffer instead of vector instructions.
* **Affected Files**: `Sources/Renderers/BitmapRenderer.swift` (New file)

#### Issue 1c: `feat: implement drawing images on context`
* **Description**: Extend `GraphicsContext` to support a drawing operation that scales and rotates an input image within a target rect frame: `context.draw(_ image: Image, in rect: Rect)`.
* **Affected Files**: 
  - [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)
  - [Sources/Core/DrawOperation.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/DrawOperation.swift)

---

## 2. Epic: Image Masking, Caching & Data Streams
**Epic Title:** `epic: implement image masking, cache layers, and data streams`  
**Labels:** `epic`, `enhancement`

### Description
Support image-based clipping masks, hardware-optimized cached drawing layers, and generic data streams for file/memory access.

```mermaid
flowchart TB
    classDef done    fill:#34C759,color:#FFFFFF
    classDef active  fill:#007AFF,color:#FFFFFF
    classDef review  fill:#30B0C7,color:#FFFFFF
    classDef next    fill:#5856D6,color:#FFFFFF
    classDef partial fill:#FF9500,color:#FFFFFF
    classDef todo    fill:#8E8E93,color:#FFFFFF

    Epic13["Epic #13: Masking, Caching & Streams"]:::todo --> I16["#16: Data Providers & Consumers"]:::todo --> I17["#17: Image I/O Metadata"]:::todo --> I14["#14: Stencil & Chroma Masking"]:::todo --> I15["#15: CGLayer Caching"]:::todo

    click Epic13 href "https://github.com/SlayerMotion/PureDraw/issues/13" "Epic #13"
    click I14 href "https://github.com/SlayerMotion/PureDraw/issues/14" "Issue #14"
    click I15 href "https://github.com/SlayerMotion/PureDraw/issues/15" "Issue #15"
    click I16 href "https://github.com/SlayerMotion/PureDraw/issues/16" "Issue #16"
    click I17 href "https://github.com/SlayerMotion/PureDraw/issues/17" "Issue #17"
```

### Child Issues

#### Issue 2a: `feat: implement stencil, alpha, and chroma-key image masking`
* **Description**: Support masking/clipping operations where drawing is filtered based on the alpha or luminance channels of a masking image, and chroma key color-range filtering.
* **Affected Files**:
  - [Sources/Core/GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift)
  - [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)

#### Issue 2b: `feat: implement hardware-optimized drawing cache layers (CGLayer)`
* **Description**: Introduce cached drawing layers (`CGLayer` equivalent) initialized from a destination context, designed for low-overhead repeated stamp/brush drawing.
* **Affected Files**: [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)

#### Issue 2c: `feat: implement data providers and data consumers (CGDataProvider)`
* **Description**: Abstract memory and file access streams (`CGDataProvider`/`CGDataConsumer` equivalents) to decouple serialization from graphics targets.
* **Affected Files**: `Sources/Core/DataProvider.swift` (New file)

#### Issue 2d: `feat: implement image I/O container metadata parsing`
* **Description**: Extract EXIF, GPS, and IPTC metadata streams from image file structures.
* **Affected Files**: `Sources/Core/ImageMetadata.swift` (New file)

---

## 3. Epic: Typography and Text Layout Engine
**Epic Title:** `epic: implement native font registration and text rendering`  
**Labels:** `epic`, `enhancement`

### Description
Support loading font files (TTF/OTF), managing text transformations, measuring layout bounds, and showing text glyphs.

```mermaid
flowchart TB
    classDef done    fill:#34C759,color:#FFFFFF
    classDef active  fill:#007AFF,color:#FFFFFF
    classDef review  fill:#30B0C7,color:#FFFFFF
    classDef next    fill:#5856D6,color:#FFFFFF
    classDef partial fill:#FF9500,color:#FFFFFF
    classDef todo    fill:#8E8E93,color:#FFFFFF

    Epic18["Epic #18: Typography & Text Layout"]:::todo --> I19["#19: Font File Parser & Glyphs"]:::todo --> I20["#20: Text State Stack & Matrix"]:::todo --> I21["#21: Text Showing Context Operations"]:::todo

    click Epic18 href "https://github.com/SlayerMotion/PureDraw/issues/18" "Epic #18"
    click I19 href "https://github.com/SlayerMotion/PureDraw/issues/19" "Issue #19"
    click I20 href "https://github.com/SlayerMotion/PureDraw/issues/20" "Issue #20"
    click I21 href "https://github.com/SlayerMotion/PureDraw/issues/21" "Issue #21"
```

### Child Issues

#### Issue 3a: `feat: implement font file parser and glyph registration`
* **Description**: Create a TTF/OTF font file parser to decode tables (`cmap`, `glyf`) to convert characters to vector paths.
* **Affected Files**: `Sources/Core/Font.swift` (New file)

#### Issue 3b: `feat: implement text state stack properties and matrix`
* **Description**: Extend graphics state to hold text CTM matrix (`CGContextSetTextMatrix`), font size, character spacing, and text rendering modes.
* **Affected Files**:
  - [Sources/Core/GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift)
  - [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)

#### Issue 3c: `feat: implement text showing context operations`
* **Description**: Add text drawing functions `showText(_:at:)` and `showGlyphs(_:at:)` to `GraphicsContext` and map them in renderers.
* **Affected Files**: [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)

---

## 4. Epic: Advanced PDF Systems
**Epic Title:** `epic: implement PDF outlines, scanning, and security model`  
**Labels:** `epic`, `enhancement`

### Description
Extend the PDF engine with outlines, page bounds, content scanning/parsing, and security decryption.

```mermaid
flowchart TB
    classDef done    fill:#34C759,color:#FFFFFF
    classDef active  fill:#007AFF,color:#FFFFFF
    classDef review  fill:#30B0C7,color:#FFFFFF
    classDef next    fill:#5856D6,color:#FFFFFF
    classDef partial fill:#FF9500,color:#FFFFFF
    classDef todo    fill:#8E8E93,color:#FFFFFF

    Epic22["Epic #22: Advanced PDF Systems"]:::todo --> I23["#23: PDF Outlines & Hyperlinks"]:::todo --> I24["#24: PDF Page Boxes & Transforms"]:::todo --> I25["#25: Low-Level PDF Scanning"]:::todo --> I26["#26: PDF Encryption & Permissions"]:::todo

    click Epic22 href "https://github.com/SlayerMotion/PureDraw/issues/22" "Epic #22"
    click I23 href "https://github.com/SlayerMotion/PureDraw/issues/23" "Issue #23"
    click I24 href "https://github.com/SlayerMotion/PureDraw/issues/24" "Issue #24"
    click I25 href "https://github.com/SlayerMotion/PureDraw/issues/25" "Issue #25"
    click I26 href "https://github.com/SlayerMotion/PureDraw/issues/26" "Issue #26"
```

### Child Issues

#### Issue 4a: `feat: implement PDF outline trees, hyperlinks, and annotations`
* **Description**: Support hierarchical document outline tables of contents, destinations, and hot-spot URL annotations.
* **Affected Files**: [Sources/Renderers/PDFRenderer.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Renderers/PDFRenderer.swift)

#### Issue 4b: `feat: support PDF boundary boxes (CropBox, BleedBox) and fit transforms`
* **Description**: Support CropBox, BleedBox, TrimBox, and ArtBox, and implement a transform calculator equivalent to `CGPDFPageGetDrawingTransform`.
* **Affected Files**: [Sources/Renderers/PDFRenderer.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Renderers/PDFRenderer.swift)

#### Issue 4c: `feat: implement low-level PDF scanning and operator parsing`
* **Description**: Build a content stream scanner (`CGPDFScanner` equivalent) to read and parse vector paths from existing PDF documents.
* **Affected Files**: `Sources/Renderers/PDFScanner.swift` (New file)

#### Issue 4d: `feat: implement PDF document encryption and user permissions`
* **Description**: Support password-based decryption (`CGPDFDocumentUnlockWithPassword`) and printing/copying permissions validation.
* **Affected Files**: [Sources/Renderers/PDFRenderer.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Renderers/PDFRenderer.swift)

---

## 5. Miscellaneous Context & Pattern Features

### Issue 5: `feat: implement graphics state parameters (antialiasing, interpolation, rendering intent)`
* **Labels**: `enhancement`, `good first issue`
* **Description**: Add `shouldAntialias`, `interpolationQuality`, and `renderingIntent` properties and context setters.
* **Affected Files**:
  - [Sources/Core/GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift)
  - [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)

### Issue 6: `feat: implement path hit-testing and point containment`
* **Labels**: `enhancement`
* **Description**: Add ray-casting winding number check on `Path`: `func contains(_ point: Point, using rule: FillRule) -> Bool`.
* **Affected Files**: [Sources/Core/Path.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/Path.swift)

### Issue 7: `feat: implement colored and uncolored repeating pattern fills`
* **Labels**: `enhancement`
* **Description**: Support colored and uncolored cell textures tiling.
* **Affected Files**:
  - [Sources/Core/GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift)
  - [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)

### Issue 8: `feat: support custom CGFunction mathematical gradients`
* **Labels**: `enhancement`
* **Description**: Support procedural math functional shadings evaluated per coordinate.
* **Affected Files**: [Sources/Core/Gradient.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/Gradient.swift)
