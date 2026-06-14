# Lesson 13: Encoding Pixels, PNG Chunks, zlib & DEFLATE

Once a path is rasterized into a grid of RGBA pixels (Lesson 11), that grid has to leave the
program as a file someone can open. This lesson covers how `PureDraw` writes a PNG with no
external library, and why *reading* one back is a strictly harder problem.

---

## 1. Core Concepts

### A PNG is a container of chunks
A PNG file is an 8-byte signature followed by a sequence of **chunks**. Each chunk is a
length, a 4-letter type, the data, and a CRC-32 checksum. The three that matter for a basic
image:

* **IHDR**, the header: width, height, bit depth, colour type. `PureDraw` always writes
  8-bit RGBA (colour type 6), the simplest universally-supported format.
* **IDAT**, the pixel data, compressed as a zlib stream.
* **IEND**, the end marker.

### Filtering
Before compression, each scanline is prefixed with a **filter byte** that selects a
per-row predictor (none / sub / up / average / Paeth). Filtering makes the data more
compressible by turning pixels into small deltas. `PureDraw` uses filter type 0 ("none")
on every row, correct and simple, trading file size for clarity.

### The compression asymmetry
The pixel bytes go into the IDAT chunk as a **zlib stream**, which wraps **DEFLATE**. Here
is the key insight of this lesson: DEFLATE's framing lets you emit **stored
(uncompressed) blocks**. So you can produce a *completely valid* zlib/PNG stream without
implementing any actual compression, just the framing and checksums. Writing is easy.
*Reading* is not: a real PNG decoder must implement full DEFLATE **inflate** (Huffman
decoding + LZ77 back-references), because other encoders *do* compress. This asymmetry is
why `PureDraw` can encode PNGs today but decoding them is a separate, larger task
(issue #103).

---

## 2. Mathematical Foundations

### The zlib stream
A zlib stream is a 2-byte header, the DEFLATE payload, and a 4-byte Adler-32 checksum of
the *uncompressed* data:

$$\texttt{zlib} = \underbrace{\texttt{0x78\ 0x01}}_{\text{CMF, FLG}} \;\Vert\; \texttt{DEFLATE blocks} \;\Vert\; \underbrace{\texttt{Adler32}(\text{raw})}_{\text{4 bytes}}$$

`0x78` encodes "DEFLATE, 32K window"; `0x01` is the check/flags byte (no preset
dictionary). The pair satisfies the zlib rule that $\text{CMF}\cdot 256 + \text{FLG}$ is a
multiple of 31.

### Stored DEFLATE blocks
A DEFLATE stream is a sequence of blocks. A *stored* block has a 3-bit header (final-flag +
type `00`), then aligns to a byte, then a 16-bit length `LEN`, its one's-complement
`~LEN`, then `LEN` literal bytes:

$$\text{block} = [\,\text{BFINAL},\ \text{BTYPE}{=}00\,] \;\Vert\; \texttt{LEN} \;\Vert\; \texttt{NLEN}{=}\sim\!\texttt{LEN} \;\Vert\; \text{raw}_{0\ldots\text{LEN}-1}$$

Because $\text{LEN} \le 65535$, data longer than 64 KB is split across multiple stored
blocks, the last marked final. No Huffman tables, no back-references, the bytes pass
through verbatim, framed.

### Two checksums, two algorithms
* **Adler-32** (zlib level): two running sums mod 65521,
  $A = 1 + \sum b_i$, $B = \sum A_i$, packed as $B \cdot 2^{16} + A$. Cheap, weak.
* **CRC-32** (chunk level): a table-driven cyclic redundancy check over the chunk type +
  data, polynomial `0xEDB88320`. Stronger; protects each chunk independently.

The encoder builds both from first principles, a 256-entry CRC table and the Adler running
sums, so the output validates in any conformant PNG reader.

---

## 3. Code Demonstration

Render a shape, encode it to PNG bytes, and confirm the structure: the signature, then an
IHDR chunk, with the pixel data carried in a stored-block zlib stream.

```swift
import Core
import Geometry
import Renderers

func encodePNG() throws {
    var context = GraphicsContext()
    context.setFillColor(Color(r: 0.95, g: 0.75, b: 0.1, a: 1.0))
    context.fillEllipse(in: Rect(x: 8, y: 8, width: 48, height: 48))

    let image = try BitmapRenderer(width: 64, height: 64).draw(context)
    let png = PNGEncoder.encode(image)   // [UInt8], a complete PNG file

    // PNG signature: 137 80 78 71 13 10 26 10
    precondition(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    // Bytes 12..16 are the first chunk's type, "IHDR".
    let ihdrType = String(bytes: png[12 ..< 16], encoding: .ascii)
    print("first chunk:", ihdrType ?? "?")   // IHDR
    print("total bytes:", png.count)
}
```

The same `zlibStored` framing is reused as a PDF `FlateDecode` stream, so one stored-DEFLATE
routine serves both the PNG and PDF back ends.

---

## 4. Exercises

1. **The 31 rule.** Verify that `0x78 0x01` satisfies $(\text{CMF} \cdot 256 + \text{FLG})
   \bmod 31 = 0$. Find another valid `FLG` for `CMF = 0x78` and explain what it would
   change.
2. **Block splitting.** A $1000 \times 1000$ RGBA image has how many raw bytes (including
   filter bytes)? How many stored DEFLATE blocks at most 65535 bytes each does it need, and
   which one carries `BFINAL = 1`?
3. **The hard half.** Sketch what a `PNGDecoder` must add that the encoder skips: Huffman
   table reconstruction and LZ77 back-reference resolution for inflate, the five unfilter
   predictors, and non-RGBA colour types. Why is the inflater the bulk of the work
   (issue #103)?
