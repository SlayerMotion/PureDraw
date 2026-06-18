# ``PureDraw``

A dependency-free, Swift-native 2D vector graphics engine.

## Overview

PureDraw draws vector graphics with no external dependencies and no platform
graphics framework: paths, gradients, images, text, and effects are described
once and rendered to several backends that agree pixel-for-pixel within
antialiasing tolerance.

You build a picture by issuing commands to a ``GraphicsContext`` (the same
state-machine model as PDF and CoreGraphics: a current path, transform, clip,
and graphics state with save/restore), then hand the recorded operations to a
renderer:

- ``BitmapRenderer`` rasterizes to a raw-RGBA ``Image`` in pure Swift.
- ``CoreGraphicsRenderer`` replays the operations through CoreGraphics on Apple
  platforms.
- ``SVGRenderer``, ``PDFRenderer``, ``PostScriptRenderer``, and
  ``CanvasRenderer`` emit the picture as documents or code.

Geometry is value types (``Point``, ``Rect``, ``AffineTransform``);
every public input is `Validatable`, so malformed values are rejected at the
boundary rather than producing undefined output.

The library is organized in one-directional layers: **Validation → Geometry →
Core → Renderers**, re-exported together as the `PureDraw` umbrella.

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

### Drawing

- ``GraphicsContext``
- ``Path``
- ``PathElement``
- ``DrawOperation``
- ``GraphicState``

### Paint

- ``Color``
- ``ColorSpace``
- ``Gradient``
- ``GradientStop``
- ``Pattern``
- ``Shadow``
- ``BlendMode``
- ``FillRule``

### Images

- ``Image``
- ``AlphaInfo``
- ``ImageMetadata``
- ``ImageDecoder``

### Text and fonts

- ``Font``
- ``VariationAxis``
- ``VariationInstance``
- ``WOFFDecoder``

### Geometry

- ``Point``
- ``Rect``
- ``AffineTransform``
- ``ProjectiveTransform``

### Renderers

- ``Renderer``
- ``BitmapRenderer``
- ``CoreGraphicsRenderer``
- ``SVGRenderer``
- ``PDFRenderer``
- ``PostScriptRenderer``
- ``CanvasRenderer``
