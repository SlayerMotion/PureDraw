# How Inflate Works

The dependency-free DEFLATE decompressor that PNG and WOFF are built on.

## Overview

PureDraw decodes PNG and WOFF without a system zlib, so it carries its own DEFLATE
(RFC 1951) inflater and zlib (RFC 1950) wrapper, in `Inflate`. This article is the
narrative; the code is `Sources/Core/Inflate.swift`, verified against the system
compressor in `PNGDecoderTests`.

### The bit stream

DEFLATE is read least-significant-bit first within each byte, which is the opposite
of how multi-byte integers elsewhere in fonts and PNG are read (most-significant
first). A small bit reader pulls 1 to several bits at a time and refills from the
byte stream as needed; getting the bit order right is the first thing that makes or
breaks an inflater.

### Blocks

The stream is a sequence of blocks, each with a 3-bit header: a final-block flag and
a 2-bit type.

- **Stored** (type 0): the data is uncompressed; after aligning to a byte boundary,
  a 16-bit length and its one's-complement precede the literal bytes. PureDraw's own
  `PNGEncoder` emits only stored blocks, which is why the round-trip test alone would
  not exercise the Huffman paths.
- **Fixed Huffman** (type 1): a predefined code table.
- **Dynamic Huffman** (type 2): the code tables are themselves Huffman-coded and
  carried in the block.

### Canonical Huffman codes

Both Huffman block types use *canonical* codes: a symbol's code is determined
entirely by the list of code lengths, so only the lengths travel in the stream. The
decoder reconstructs each table by counting how many codes have each length, then
assigning codes in order of increasing length and, within a length, increasing
symbol. Decoding then accumulates bits and compares against the first code of each
length (the puff.c technique): no explicit tree is built, which keeps the decoder
small and allocation-light. `Huffman.init(codeLengths:)` is deliberately
non-failable, mapping an empty input to an empty table, so a malformed block returns
nil from `decode` rather than trapping.

### Back references (LZ77)

A decoded literal symbol below 256 is a byte. Symbol 256 ends the block. Symbols
above 256 are *length* codes: each, with a few extra bits, gives a match length, and
a following *distance* code (also with extra bits) gives how far back to copy from.
The copy reads from the output produced so far, so overlapping copies (distance less
than length) repeat a recent run, which is how runs compress. Bounds are checked on
every copy: a distance past the start of the output is rejected, not wrapped.

## The zlib wrapper

`Inflate.zlib` adds RFC 1950 framing: a two-byte header (the common `0x78` plus a
flags byte) and a trailing Adler-32 checksum of the *uncompressed* data, which the
decoder recomputes and verifies. PNG's IDAT and WOFF's compressed tables are zlib
streams, so they go through `zlib`; raw DEFLATE goes through `deflate`.

## Using it

The codecs that ride on `Inflate` are reached through their public entry points:

@Snippet(path: "PureDraw/Snippets/decoding")
