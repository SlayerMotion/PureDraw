# Image and Font Containers

How PNG and WOFF wrap their payloads on top of Inflate.

## Overview

PNG and WOFF are containers: framing around a zlib-compressed payload. Both reuse
`Inflate` (see <doc:InflateAlgorithm>) and add format-specific reassembly.

## PNG

`ImageDecoder` parses the 8-byte signature and then a sequence of chunks (length,
4-byte type, data, CRC). It reads `IHDR` for the dimensions and color type, gathers
the `IDAT` chunks into one zlib stream, inflates it, and reconstructs the image.

The reconstruction step is the part unique to PNG: each scanline begins with a
**filter** byte chosen by the encoder to make the row more compressible, and the
decoder must undo it. The five filters predict each byte from its neighbors:

- **None**: the byte stands as is.
- **Sub**: add the byte one pixel to the left.
- **Up**: add the byte directly above.
- **Average**: add the floor of the average of left and above.
- **Paeth**: add whichever of left, above, or upper-left is closest to their linear
  predictor `left + above - upperLeft`.

Reconstruction is sequential and stateful: each recovered byte feeds the prediction
for the bytes below and to its right. The recovered samples are then assembled into
straight-alpha RGBA according to the color type (grayscale, RGB, palette, with or
without alpha) at 8 bits. JPEG, 16-bit, and interlaced PNG are reported as
unsupported rather than guessed.

## WOFF 1.0

`WOFFDecoder` is the inverse of the WOFF wrapping. A WOFF is an sfnt font whose
tables are individually zlib-compressed (or stored when compression would not help),
behind a 44-byte header and a 20-byte-per-entry table directory. Decoding:

1. read the directory, and for each table inflate it when its compressed length is
   below its original length, otherwise take it stored;
2. sort the table records by tag, as an sfnt requires;
3. rebuild the sfnt: the offset table with correct binary-search fields, then the
   records pointing into 4-byte-aligned table data.

`Font(woff:)` runs this and parses the result in one step. The metadata and private
blocks are ignored; WOFF2 (Brotli plus a transformed `glyf`/`loca`) is a different
format and is not handled here.
