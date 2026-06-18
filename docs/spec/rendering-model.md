# PureDraw Rendering Model (normative)

| Field | Value |
|---|---|
| **Status** | draft |
| **Tracking issue** | [#123](https://github.com/SlayerMotion/PureDraw/issues/123) |
| **Program** | [docs/knuth-program.md](../knuth-program.md), epic [#127](https://github.com/SlayerMotion/PureDraw/issues/127) |

This is the normative definition of what a PureDraw picture *means*. The library is
one conforming implementation of this document, not the other way round. The key
words MUST, MUST NOT, SHOULD, and MAY are used in the IETF sense.

## 1. Scope and conformance

A **picture** is a `GraphicsContext`: an ordered list of `DrawOperation`s, each
paired with the `GraphicState` in effect when it was recorded. A **renderer**
consumes a picture and produces an output (pixels, or a document, or code).

A renderer **conforms** if, for every picture in the conformance corpus
(SlayerMotion/PureConformance#6), its rasterized output matches the reference
output within the tolerance of §8. `BitmapRenderer` is the **reference
rasterizer**: where this document does not fix an exact pixel value (antialiasing,
transcendental functions), the reference rasterizer's output is canonical and
conformance is defined by the tolerance, not by bit-equality. Document and code
renderers (SVG, PDF, PostScript, Canvas) conform if rasterizing their output
reproduces the reference within tolerance, and they MUST raise
`UnsupportedOperationError` for an operation they cannot represent rather than
silently dropping it.

## 2. Coordinate system and pixel model

- Coordinates are `Double` in a 2D plane. Geometry is top-left origin: x increases
  right, y increases down. (Font glyph outlines are y-up in font units and are
  flipped by the text pipeline; see §9.)
- A raster output is `width * height` pixels, row-major, 4 bytes per pixel,
  **straight (non-premultiplied) RGBA**, 8 bits per component, in the device RGB
  color space unless the picture specifies otherwise.
- Every public input MUST be finite and in range; non-finite or out-of-range
  values are rejected at the boundary (the `Validatable` conformances), never
  rendered to undefined output. Sentinel rectangles (`Rect.null`, `Rect.infinite`)
  are the documented exception.

## 3. Graphics state

The `GraphicState` carries the current transform (CTM), fill and stroke colors,
line width/cap/join/miter/dash, alpha, blend mode, clip path stack, mask, shadow,
and text parameters. `saveGState()` / `restoreGState()` push and pop the whole
state as a stack. An operation is rendered with exactly the state captured when it
was recorded; later state changes MUST NOT affect already-recorded operations.

## 4. Path and fill rules

A `Path` is a sequence of `PathElement`s (`move`, `line`, `quadCurve`,
`cubicCurve`, `close`). A subpath opens with a `move`. Filling uses a `FillRule`:

- `.winding` (nonzero): a point is inside iff the signed crossing number is nonzero.
- `.evenOdd`: a point is inside iff the crossing count is odd.

Stroking converts the path to a fill region per the line width, cap, join, miter
limit, and dash pattern, then fills it; the conversion is `Path.strokedOutline`.

## 5. Drawing command vocabulary

The authoritative enumeration is `DrawOperation.Kind`; this section fixes the
semantics. Coordinates are interpreted in the operation's CTM.

- `fill(path, rule)` / `stroke(path)`: paint the fill region (§4) with the current
  fill / stroke color, composited per §7.
- `drawLinearGradient` / `drawRadialGradient` / `drawConicGradient`: paint the
  current clip region with the gradient evaluated along the given geometry; the
  `GradientDrawingOptions` control whether the regions before the first and after
  the last stop are filled with the end colors or left uncovered.
- `drawImage(image, rect)`: sample `image` into `rect`. `drawImageProjective`
  applies a `ProjectiveTransform` (a perspective warp).
- `showText(...)`: render glyph outlines (or bitmaps, §9) at the position and text
  matrix, in the given drawing mode (fill, stroke, clip).
- `beginTransparencyLayer` / `endTransparencyLayer`: render the enclosed
  operations into an isolated layer, then composite it once with the group alpha.
- clip / transform / mask / shadow push and pop (recorded on `GraphicState`):
  intersect the clip, concatenate the CTM, modulate by a mask, or attach a shadow,
  for the operations until the matching pop.
- `dropShadow(path)`: a shadow silhouette of `path`. `drawLayer(layer, rect)`:
  composite a nested layer's own picture.

## 6. Paint

Colors live in a `ColorSpace` (device RGB, gray, or CMYK) with components in
`0...1`; conversion between spaces is defined by `Color`. Gradients are ordered
`GradientStop`s (location in `0...1`); the color between stops is the linear
interpolation of the surrounding stops. Patterns tile a cell picture.

## 7. Compositing and blending

Source-over is the default. The separable and non-separable blend modes and the
Porter-Duff operators follow the **W3C Compositing and Blending Level 1** math
exactly, computed in straight-alpha RGBA: separable modes apply the blend function
per channel; non-separable modes (hue, saturation, color, luminosity) use the
whole-triple Lum/Sat transfer of §9.3; Porter-Duff uses the coverage form
`co = Fa*cs + Fb*cd`. A renderer that cannot express a mode natively MUST compute
it itself rather than approximate.

## 8. Antialiasing and the conformance tolerance

Exact pixel values are not fixed by this document, because antialiasing and libm
transcendentals differ across rasterizers. Conformance is defined by per-pixel
difference against the reference rasterizer: the **mean** absolute difference and
the **maximum** absolute difference over all channels MUST be within the tolerance
the conformance corpus records for each picture (the parity tests use this same
mean/max form). Two renderers that both conform therefore agree within twice the
tolerance.

## 9. Text and images

Glyph outlines come from `glyf` (quadratic), `CFF ` / `CFF2` (Type 2), in font
units with y up; the text matrix maps them into the picture. Color fonts expose
layers (`COLR`/`CPAL`) or embedded PNG bitmaps (`sbix`); variable fonts are
interpolated at an instance (`fvar`/`gvar`/`avar`). Images are decoded to straight
RGBA before sampling.

## 10. The SVG path normal form (normative, proven)

`SVGPathData` defines a canonical **normal form**: absolute `M L Q C Z`, single
space separated, coordinates as the shortest decimal that round-trips the
`Double`, a leading `M` per subpath. The five commands are a single table
(`canonicalCommands`) from which both the printer and the strict parser derive.

**Theorem (round-trip).** For every well-formed element sequence (one whose
subpaths open with a `move`), `parseCanonical(print(x)) == x`. This holds by
construction and is proven in `SVGPathRoundTripProofTests` (base lemma: per-command
`build`/`match` are mutual inverses; inductive step: checked over generated
sequences; rests on `Double.description` being the shortest round-trippable form).
The full SVG grammar (relative, `H`/`V`, `S`/`T`, arcs) is accepted by lowering it
into the normal form; that lowering is deliberately one-way.

## 11. Versioning and freeze (proposal)

Proposed for owner ratification: at 1.0, the semantics in §§2-10 are **frozen**.
After the freeze, changes to defined behavior are bug fixes only (the behavior was
already wrong against this document); new capabilities go to a clearly numbered
next line and extend, never redefine, the frozen semantics. The conformance corpus
is versioned against this document.
