# Changelog

All notable changes to PureDraw are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Affine `drawImage` now antialiases its destination edge. With
  `shouldAntialias` enabled, a pixel the transformed image rect crosses is
  supersampled on a 4x4 grid and coverage-weighted, so a rotated or non-integer
  image edge fades instead of stepping (at parity with the projective image path).
  Fully-interior pixels still take a single centre sample, so integer-aligned
  draws are byte-for-byte unchanged, and `shouldAntialias == false` keeps the
  binary edge. Source sampling stays governed by `interpolationQuality`,
  independent of destination coverage (#97).

## [0.2.0] - 2026-06-14

### Added

- `Path.addAppleRoundedRect(in:cornerRadius:)` reproduces Apple's exact
  continuous corner pixel-for-pixel: the same shape
  `UIBezierPath(roundedRect:cornerRadius:)` and SwiftUI's
  `RoundedCornerStyle.continuous` produce, using the control-point ratios
  extracted from `UIBezierPath` (each corner is three cubic Béziers consuming
  `1.528665` times the radius).
- `Path.addContinuousRoundedRect(in:cornerRadius:smoothing:)` produces a
  *tunable* continuous (squircle) corner: curvature ramps smoothly from the
  straight edge into the corner. Each corner is three cubic Béziers (ease-in,
  shortened arc, ease-out) following Figma's reverse-engineering of Apple's
  corners; `smoothing` runs 0 (circular) to 1, default 0.6. (Apple's exact
  corner is not a superellipse: a superellipse fits Apple worse than a circle.)
- Text is recorded as a single high-level `showText` draw operation.
  `GraphicsContext.textLoweredCommands` expands it to glyph outline
  fills/strokes (so pixel and PostScript/Canvas backends are unchanged), while
  SVG and PDF can read the raw operation to emit native selectable text.
- `SVGRenderer` emits `<text>` elements for `showText(_:)` runs, so exported
  SVG carries real selectable, searchable text. Glyph-index runs (no source
  string) and transformed text fall back to outlines.
- `PDFRenderer` embeds the TrueType program as a Type 0 / CIDFontType2 font
  (Identity-H, FontFile2, per-glyph widths, ToUnicode CMap) and emits `Tj`
  text objects for `showText(_:)` runs, so exported PDFs carry real selectable,
  searchable text. `Font.sfntData` exposes the raw font bytes for embedding.
- `Pattern`, the `CGPattern` equivalent: a tiling cell recorded into its own
  context and used via `GraphicsContext.setFillPattern(_:)`. Colored patterns
  carry their own colors; uncolored (stencil) patterns paint with the current
  fill color. Pattern fills expand into tiled, clipped cell operations at
  record time, so every backend renders them with no special support.
- `Gradient(samples:_:)` builds a gradient from a procedural color function,
  the `CGFunction` shading equivalent, sampled into ordinary stops so every
  backend renders it unchanged.
- PDF document features on `PDFRenderer`: page boundary boxes (CropBox,
  BleedBox, TrimBox, ArtBox) with a `drawingTransform` fit calculator, link
  annotations (`PDFLink`: URI or internal destination), hierarchical outlines
  (`PDFOutlineItem`), and standard-security-handler encryption
  (`PDFEncryption`: user/owner passwords and permission flags, RC4-40 with
  pure Swift MD5/RC4).
- `PDFScanner`, the `CGPDFScanner` equivalent: tokenizes content streams and
  dispatches operator callbacks with parsed operand stacks.
- `Font`, a pure Swift TrueType parser: `cmap` formats 0/4/6/12, short and
  long `loca`, simple and composite `glyf` outlines decoded to `Path` values
  in font units, `hmtx` advance widths, and `.ttc` collections.
- CFF / OpenType (`OTTO`) outline support: a CFF table parser (INDEX, DICT,
  charstrings, subroutines) and a Type 2 charstring interpreter feed glyph
  outlines through the same `Font.outline` API, so PostScript-outlined fonts
  work alongside TrueType ones.
- Text state and showing: `font`, `fontSize`, `characterSpacing`, and
  `textDrawingMode` on the graphics state, `textMatrix`/`textPosition` on the
  context, and `showText(_:at:)`/`showGlyphs(_:at:)` which record glyph
  outlines as plain fill/stroke operations, so every backend renders text as
  vectors with no per-renderer work.
- `Layer`, the `CGLayer` equivalent: record into `layer.context`, stamp with
  `GraphicsContext.draw(_:in:)` or `draw(_:at:)`. `BitmapRenderer` rasterizes
  each layer once per pass and reuses the cached image; `CoreGraphicsRenderer`
  renders into a native `CGLayer`; vector backends inline the layer's
  commands per stamp via `GraphicsContext.flattenedCommands`.
- `DataProvider` and `DataConsumer`, the `CGDataProvider`/`CGDataConsumer`
  equivalents, plus `Image(provider:)` and `PNGEncoder.encode(_:to:)`.
- `ImageMetadata.parse` extracts dimensions, EXIF camera fields, GPS
  coordinates, and PNG text chunks from PNG, JPEG, and TIFF containers.
- `PNGEncoder.encode(_:)` turns any `Image` into a standards-correct PNG
  (8-bit RGBA, stored deflate blocks) with no external dependencies, on every
  supported platform.
- Golden-image tests pin `BitmapRenderer` output byte-for-byte (fills,
  strokes, gradients, images, masks, transparency layers), so the macOS,
  Linux, and Windows CI gates now enforce pixel-identical rasterization.
- `BitmapRenderer` fills with a scanline pass and coverage-based anti-aliasing,
  honoring `GraphicState.shouldAntialias` (previously unread). Aliased
  rendering keeps the old pixel-center behavior, and the scanline pass replaces
  the O(pixels x segments) per-pixel containment loop.
- `Path.toPolylines()` flattens a path into per-subpath polylines that
  preserve whether each subpath was explicitly closed.
- `BitmapRenderer` strokes with true join geometry: miter joins honor
  `miterLimit` and fall back to bevel, bevel joins cut the outer corner, and
  round joins keep their disk. The whole stroke renders as one
  winding-consistent shape, so overlapping segments blend exactly once even
  with translucent stroke colors.
- `Image.sampledColor(u:v:quality:)` samples at normalized coordinates with
  nearest-neighbor for `.none` and premultiplied bilinear filtering for every
  other `InterpolationQuality`. `BitmapRenderer` image drawing now honors the
  state's interpolation quality (the default interpolates, matching
  CoreGraphics), and `CoreGraphicsRenderer` forwards the quality to its
  `CGContext`. Mask sampling stays nearest-neighbor in both renderers.
- Image-based clipping masks: `GraphicsContext.clip(to:mask:)`, honored by
  `BitmapRenderer` and `CoreGraphicsRenderer`.
- Color masking on `Image` via `maskingColors`, applied consistently by both
  pixel renderers (no-alpha layouts only, matching CoreGraphics semantics).
- `Image.pixelColor(x:y:)` and `Image.maskCoverage(x:y:)` for per-pixel
  sampling across gray, RGB, and CMYK layouts.
- `AlphaInfo.hasAlpha`, `AlphaInfo.isAlphaFirst`, and
  `AlphaInfo.isPremultiplied`.
- Validation now rejects images whose `bitsPerComponent` is not 8, making the
  assumption baked into pixel decoding explicit.

### Fixed

- `BitmapRenderer` now applies `dashPattern` / `dashPhase` when stroking. The
  software path previously ignored the dash and painted a solid line, diverging
  from the vector renderers (Canvas, PDF, SVG), which already emit it. Each "on"
  span is stroked as its own capped run; dash lengths and phase scale with the
  CTM like the line width, an odd-count pattern repeats to even, and an empty
  pattern stays solid (#98).
- Validation now rejects a fill pattern with a non-positive `xStep`/`yStep`,
  closing the last reflection gap (pattern bounds, text position, and text
  matrix were already validated through the command graph).
- `BitmapRenderer` throws `ValidationError` on non-positive dimensions instead
  of trapping at buffer allocation.
- Validation now rejects unbalanced transparency layers (which produced
  unclosed SVG groups), image layouts whose `bitsPerPixel` is too small for
  the color space or whose `bytesPerRow` cannot hold a row, `drawLayer` stamps
  with non-positive dimensions, and fonts with `unitsPerEm == 0`.
- The validation walker now visits each reference-type instance once, so
  cyclic object graphs (such as a layer drawn into itself) validate instead
  of overflowing the stack.
- `BitmapRenderer` no longer strokes a phantom closing segment on open paths:
  stroking now flattens through `Path.toPolylines()`, which preserves whether
  each subpath was explicitly closed.
- `CoreGraphicsRenderer` mask clipping rendered nothing: the vertical flip was
  composed with CoreGraphics ordering on `AffineTransform` builders that append
  instead of prepending, pushing the clip off-canvas. The mask and drawing
  transforms now compose in the correct order.
- `BitmapRenderer` now evaluates the clip path in device space when stroking
  segments and square caps; previously a non-identity CTM clipped strokes
  against the untransformed clip path.

### Changed

- `CoreGraphicsRenderer` converts each distinct mask image to DeviceGray at
  most once per render pass instead of once per operation.
- **Breaking:** `Image.init` throws `ValidationError` when the data buffer is
  smaller than `height * bytesPerRow`, instead of trapping via `precondition`.
  Construction sites must use `try`.
- **Breaking:** `Renderer` now requires `draw(_:)` instead of `render(_:)`.
  `render(_:)` is provided by a protocol extension that validates the context
  first and throws `ValidationErrorCollection` for invalid input, so every
  backend enforces validation. Existing call sites of `render(_:)` keep
  working; custom renderers must rename their implementation to `draw(_:)`.
