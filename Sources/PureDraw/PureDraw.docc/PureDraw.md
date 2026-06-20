# ``PureDraw``

A dependency-free, Swift-native 2D vector graphics engine.

## Overview

PureDraw draws vector graphics with no external dependencies and no platform
graphics framework: paths, gradients, images, text, and effects are described
once and rendered to several backends that agree pixel-for-pixel within
antialiasing tolerance.

You build a picture by issuing commands to a `GraphicsContext` (the same
state-machine model as PDF and CoreGraphics: a current path, transform, clip,
and graphics state with save/restore), then hand the recorded operations to a
renderer:

- `BitmapRenderer` rasterizes to a raw-RGBA `Image` in pure Swift.
- `CoreGraphicsRenderer` replays the operations through CoreGraphics on Apple
  platforms.
- `SVGRenderer`, `PDFRenderer`, `PostScriptRenderer`, and `CanvasRenderer` emit
  the picture as documents or code.

Geometry is value types (`Point`, `Rect`, `AffineTransform`); every public input
is `Validatable`, so malformed values are rejected at the boundary rather than
producing undefined output.

`PureDraw` is an umbrella that re-exports its layered modules in one direction,
**Validation, Geometry, Core, Renderers**. Because the umbrella owns no symbols
of its own, the type reference below names each type in code font and the
constituent modules carry the symbol pages; the guides are the entry points.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:ChoosingARenderer>
- <doc:DecodingImagesAndFonts>

### Internals (how the codecs work)

- <doc:InflateAlgorithm>
- <doc:ImageAndFontContainers>
- <doc:Type2Charstrings>
- <doc:VariableFontInterpolation>

## Type reference

The public surface, grouped by layer. The symbol pages live in the constituent
modules `Core`, `Geometry`, and `Renderers`.

**Drawing** in `Core` is `GraphicsContext`, `Path`, `PathElement`,
`DrawOperation`, and `GraphicState`. **Paint** in `Core` is `Color`,
`ColorSpace`, `Gradient`, `GradientStop`, `Pattern`, `Shadow`, `BlendMode`, and
`FillRule`. **Images** in `Core` is `Image`, `AlphaInfo`, `ImageMetadata`, and
`ImageDecoder`. **Text and fonts** in `Core` is `Font`, `VariationAxis`,
`VariationInstance`, and `WOFFDecoder`.

**Geometry** is `Point`, `Rect`, `AffineTransform`, and `ProjectiveTransform`.

**Renderers** is `Renderer`, `BitmapRenderer`, `CoreGraphicsRenderer`,
`SVGRenderer`, `PDFRenderer`, `PostScriptRenderer`, and `CanvasRenderer`.
