# Choosing a Renderer

Pick the backend for the output you need; the drawing code stays the same.

## Overview

Every backend conforms to ``Renderer`` and consumes the same
``GraphicsContext``, so you describe a picture once and render it through
whichever backend produces the output you want. They differ only in their
`Output` type.

### Raster output

- ``BitmapRenderer`` rasterizes to a raw-RGBA ``Image`` in pure Swift on any
  platform. It is the reference rasterizer the other backends are validated
  against, so reach for it when you want pixels you fully control.
- ``CoreGraphicsRenderer`` replays the commands through CoreGraphics on Apple
  platforms, for native integration when you already work with CGContext.

### Document and code output

- ``SVGRenderer`` emits an SVG document.
- ``PDFRenderer`` emits a PDF document.
- ``PostScriptRenderer`` emits a PostScript program.
- ``CanvasRenderer`` emits a script that redraws the picture through a 2D canvas
  drawing API.

### Rendering the same picture several ways

Because the backends share the ``GraphicsContext`` contract, one recorded
context can feed any number of renderers:

```swift
var context = GraphicsContext()
context.setFillColor(Color(red: 0.2, green: 0.5, blue: 0.9))
context.fill(Rect(x: 0, y: 0, width: 64, height: 64))

let image = try BitmapRenderer(width: 64, height: 64).render(context)
let svg = try SVGRenderer(width: 64, height: 64).render(context)
```

The reference rasterizer and the other backends agree on the same picture
within antialiasing tolerance, so switching backends does not change what the
drawing means.
