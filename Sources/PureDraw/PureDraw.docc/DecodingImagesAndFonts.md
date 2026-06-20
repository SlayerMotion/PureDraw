# Decoding Images and Fonts

Turn encoded image and font bytes into pixels and glyph outlines.

## Overview

PureDraw decodes common image and font containers in pure Swift, with no system
codec. Decoders are strict: unsupported or malformed input throws or returns
`nil` rather than guessing, so a caller always knows whether decoding happened.

### Images

`ImageDecoder` turns encoded bytes into a raw-RGBA `Image`. It handles PNG
(8-bit grayscale, RGB, RGBA, grayscale+alpha, and palette) and `data:` URIs
wrapping a base64 PNG.

```swift
import PureDraw

let image = try ImageDecoder.decode(pngBytes)        // [UInt8] -> Image
let fromURI = try ImageDecoder.decode(dataURI: uri)  // "data:image/png;base64,..."
```

Unsupported formats and malformed data throw `ImageDecoder.Error`.

### Fonts

Parse a TrueType or OpenType font from its sfnt bytes, then map characters to
glyphs and read their outlines as `Path` values (in font units, y up).

```swift
let font = try Font(data: sfntBytes)
if let glyph = font.glyphIndex(for: "A"),
   let outline = font.outline(forGlyph: glyph) {
    // draw `outline` through a GraphicsContext
}
```

Outlines come from `glyf` (TrueType), `CFF `, or `CFF2` (the variable-font
PostScript form) transparently. A WOFF 1.0 wrapper is decoded with
`Font.init(woff:)`.

### Color and bitmap glyphs

Color fonts expose their glyphs as layers or bitmaps rather than plain outlines:

```swift
// COLR/CPAL: fill each layer's outline with its palette color, back to front.
if let layers = font.colorLayers(forGlyph: glyph) {
    for layer in layers {
        // fill font.outline(forGlyph: layer.glyph) with layer.color
    }
}

// sbix: an embedded PNG bitmap, decoded to an Image.
let bitmap = font.glyphBitmap(forGlyph: glyph)
```

### Variable fonts

For an OpenType variable font, inspect the axes and interpolate an outline at a
chosen instance. Axes you omit stay at their default value.

```swift
for axis in font.variationAxes {
    print(axis.tag, axis.minValue, axis.defaultValue, axis.maxValue)
}

let bold = font.outline(forGlyph: glyph, variations: ["wght": 700])
```

Normalization honors the font's `avar` table, and both simple and composite
glyphs are interpolated, so the result matches the platform shaper.
