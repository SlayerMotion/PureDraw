# GitHub Issue Templates for CoreGraphics/Quartz 2D Gaps

This document defines ready-to-file GitHub issues to address all missing features and architectural gaps in `PureDraw`, categorized by phase.

---

## Phase 1: Core Context & Geometry Extensions

### Issue 1: `feat: implement graphics state parameters (antialiasing, interpolation, rendering intent)`
* **Labels**: `enhancement`, `good first issue`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Extend the graphics state stack to support standard Quartz context controls like anti-aliasing, image interpolation settings, font smoothing, and rendering intents.

## Requirements
1. **State Properties**: Add the following to [GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift):
   - `shouldAntialias: Bool` / `allowsAntialiasing: Bool`
   - `interpolationQuality: InterpolationQuality` (none, low, medium, high)
   - `renderingIntent: RenderingIntent` (default, perceptual, relativeColorimetric, saturation, absoluteColorimetric)
   - `shouldSmoothFonts: Bool` / `allowsFontSmoothing: Bool`
   - `shouldSubpixelPositionFonts: Bool`
2. **Context Setters**: Add matching mutating APIs in [GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift).
3. **Renderer Integration**: Adapt renderers (PDF, SVG) to respect/serialize these flags where supported.

## Affected Files
- [Sources/Core/GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift)
- [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)
```

---

### Issue 2: `feat: implement path hit-testing and point containment`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Provide geometric APIs to check if an arbitrary user space coordinate falls inside the boundaries of a path.

## Requirements
1. **Geometric Containment**: Add a check function on `Path` conforming to `CGPathContainsPoint`:
   - `func contains(_ point: Point, using rule: FillRule) -> Bool`
2. **Context API**: Add `context.pathContains(point, using: rule)` in `GraphicsContext`.
3. **Algorithm**: Implement standard ray-casting or winding number calculations for polygons and Bezier subpaths.

## Affected Files
- [Sources/Core/Path.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/Path.swift)
- [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)
```

---

## Phase 2: Images & Masking

### Issue 3: Epic: Bitmap Images and Rasterization Support
* **Labels**: `epic`, `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed. Master epic tracking raster image import/drawing and memory buffer rasterization.

## Description
Introduce a native structure representing raw raster pixel data (RGBA) and a bitmap graphics context to render paths onto pixel memory buffers.

## Requirements
1. **Image Type**: Raw pixel matrix structure supporting float components, premultiplied alpha formats, and alpha-only masks.
2. **Bitmap Context Renderer**: An export engine targeting memory buffers (`CGBitmapContext` equivalent).
3. **Image Drawing**: Context command `context.draw(_ image: Image, in rect: Rect)`.

## Affected Files
- [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)
- [Sources/Core/DrawOperation.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/DrawOperation.swift)
```

---

### Issue 4: `feat: implement stencil, alpha, and chroma-key image masking`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed. Gated on the implementation of the Bitmap Image Epic.

## Description
Support masking/clipping operations where drawing is filtered based on the alpha or luminance channels of a masking image.

## Requirements
1. **Stencil Masking**: Intersect current clip area with an alpha mask (`context.clipToMask(_:in:)`).
2. **Chroma-Key Masking**: Color range parameters to mask out background colors during image drawing.

## Affected Files
- [Sources/Core/GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift)
- [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)
```

---

### Issue 5: `feat: implement hardware-optimized drawing cache layers (CGLayer)`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed. Gated on the implementation of the Bitmap Image Epic.

## Description
Introduce hardware-optimized cache layers (`CGLayer` equivalent) designed for caching vector graphics relative to a destination context for repeated drawing.

## Requirements
1. **Cache Layer**: An offscreen rendering structure initialized from a destination context, inheriting its scale, color space, and device features.
2. **Fast Draw**: `context.draw(_ layer: CacheLayer, at point: Point)` to replay cached commands with minimal overhead.

## Affected Files
- [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)
```

---

### Issue 6: `feat: implement image I/O container metadata parsing`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Provide decoupled header parsing to extract EXIF, GPS, and IPTC metadata streams from image file structures.

## Requirements
1. **Metadata Source**: Parse image headers to collect metadata dictionaries without decoding full pixel frames.
2. **Metadata Destination**: Pack metadata blocks during image save/export operations.

## Affected Files
- [Sources/Core/DrawOperation.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/DrawOperation.swift)
```

---

### Issue 7: `feat: implement data providers and data consumers (CGDataProvider)`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Abstract memory and filesystem access using Data Providers (`CGDataProvider` equivalent) and Data Consumers (`CGDataConsumer` equivalent) to decouple data serialization from graphic targets.

## Requirements
1. **DataProvider**: Stream reader abstraction supporting memory blocks, URL files, and sequential/direct-access callbacks.
2. **DataConsumer**: Stream writer abstraction targeting memory segments, URLs, or dynamic buffers.

## Affected Files
- [Sources/Core/DrawOperation.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/DrawOperation.swift)
```

---

## Phase 3: Fills & Patterns

### Issue 8: `feat: implement colored and uncolored repeating pattern fills`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Support repeating tiling pattern fills (colored and uncolored cells) inside stroke and fill commands.

## Requirements
1. **Pattern Definition**: Bounding cell, phase offsets, spacing step sizes, and a registration closure.
2. **Colored Patterns**: Repeating cell graphics with local color styles.
3. **Uncolored Patterns**: Masking cell templates inheriting the context's current fill/stroke color.

## Affected Files
- [Sources/Core/GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift)
- [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)
```

---

### Issue 9: `feat: support custom CGFunction mathematical gradients`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Provide arbitrary gradient shadings evaluated programmatically using math functions or closures.

## Requirements
1. **Function Shading**: Provide a math coordinator or coordinate closure that yields color values per coordinate.
2. **PDF Shading Dictionary**: Adapt `PDFRenderer` to export function shading definitions.

## Affected Files
- [Sources/Core/Gradient.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/Gradient.swift)
- [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)
```

---

## Phase 4: Typography

### Issue 10: Epic: Typography and Text Layout Engine
* **Labels**: `epic`, `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed. Master epic tracking font file registration and glyph layout.

## Description
Support loading font files (TTF/OTF), managing text transformations, measuring layout bounds, and showing text glyphs.

## Requirements
1. **Font Registration**: TTF/OTF parser loading tables (`cmap`, `glyf`) to convert characters to vector paths.
2. **Text State**: Maintain font size, text matrix, rendering mode, and spacing.
3. **Text Operations**: `showText(_:at:)` and `showGlyphs(_:at:)`.

## Affected Files
- [Sources/Core/GraphicsContext.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicsContext.swift)
- [Sources/Core/GraphicState.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Core/GraphicState.swift)
```

---

## Phase 5: PDF Outlines, Scanning & Decryption

### Issue 11: `feat: implement PDF outline trees, hyperlinks, and annotations`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Extend `PDFRenderer` to support table of contents outline trees, inter-document destinations, and coordinate-based URL hyperlinks.

## Requirements
1. **Outlines**: A hierarchical outline tree matching the PDF Outline Dictionary.
2. **Annotations**: Web links mapping rect coordinates to URI actions.

## Affected Files
- [Sources/Renderers/PDFRenderer.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Renderers/PDFRenderer.swift)
```

---

### Issue 12: `feat: support PDF boundary boxes (CropBox, BleedBox) and fit transforms`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Support specifying margins and boundary boxes for pages, and calculating auto-fit drawing transformation matrices.

## Requirements
1. **Boundary Boxes**: Support CropBox, BleedBox, TrimBox, and ArtBox parameters.
2. **Page Drawing Transform**: Implement a transform calculator equivalent to `CGPDFPageGetDrawingTransform` to fit and center page boundaries into a target rect.

## Affected Files
- [Sources/Renderers/PDFRenderer.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Renderers/PDFRenderer.swift)
```

---

### Issue 13: `feat: implement low-level PDF scanning and operator parsing`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Build a content stream scanner (`CGPDFScanner` equivalent) to read and parse vector paths and instructions from existing PDF documents.

## Requirements
1. **Tokenizer**: Parse page content streams into tokens.
2. **Operator Table**: Associate callback hooks with PDF operator symbols.
3. **Operand Stack**: Support popping values off the evaluation stack (PopName, PopStream, PopNumber).

## Affected Files
- [Sources/Renderers/PDFRenderer.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Renderers/PDFRenderer.swift)
```

---

### Issue 14: `feat: implement PDF document encryption and user permissions`
* **Labels**: `enhancement`

```markdown
## Status (2026-06-10)
Status: Proposed.

## Description
Provide password-based decryption for encrypted PDF documents and permission-checking hooks.

## Requirements
1. **Password Decryption**: Decrypt files using user or owner password keys (40 to 128 bits).
2. **Permission Check**: Query printing/copying permissions to enforce document security.

## Affected Files
- [Sources/Renderers/PDFRenderer.swift](file:///Volumes/Code/DeveloperExt/public/PureDraw/Sources/Renderers/PDFRenderer.swift)
```
