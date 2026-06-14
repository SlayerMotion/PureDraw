# Sources & Provenance

Every external source that participated in PureDraw's implementation, mapped to the
file or feature it informed. Sources are grouped by role: **specifications** the code
must conform to, **algorithms** it implements, **articles** it reverse-engineers or
follows, and the **books** behind the imaging model. A citation that appears in the
source itself is marked *(in code)*.

---

## File formats & wire specifications

These define byte-for-byte output, so the implementation follows them exactly.

| Source | Informs | File |
|---|---|---|
| **PNG (Portable Network Graphics) Specification, 2nd ed.** — W3C Recommendation / ISO/IEC 15948:2004 | Chunk framing (length/type/data/CRC), IHDR/IDAT/IEND, 8-bit RGBA colour type 6, filter type 0, signature bytes | `Renderers/PNGEncoder.swift` |
| **RFC 1950 — ZLIB Compressed Data Format** | The zlib stream wrapper (`0x78 0x01` header, Adler-32 trailer) *(in code)* | `PNGEncoder.zlibStored` |
| **RFC 1951 — DEFLATE Compressed Data Format** | Stored (uncompressed) block framing: `BFINAL`/`BTYPE`, `LEN`/`~LEN` *(in code: "stored deflate blocks")* | `PNGEncoder.zlibStored` |
| **Adler-32** (defined in RFC 1950) | The zlib checksum: two running sums mod 65521 | `PNGEncoder.adler32` |
| **CRC-32** — ITU-T V.42 / ISO 3309, reflected polynomial `0xEDB88320` | Per-chunk PNG checksum | `PNGEncoder.crc32` |
| **PDF Reference 1.4** (Adobe) / **ISO 32000-1** | Path-construction operators (`m`, `l`, `c`), the `FlateDecode` stream, and the encryption permission flags *(in code: "exactly as PDF 1.4 defines them")* | `Renderers/PDFRenderer.swift`, `PDFEncryption.swift`, `Core/Path.swift` |
| **PostScript Language Reference, 3rd ed.** (Adobe, the "Red Book") | The PostScript Level 3 / EPS output *(in code: "PostScript Level 3 (EPS)")* | `Renderers/PostScriptRenderer.swift` |
| **SVG 1.1** — W3C Recommendation | The SVG export, the `2000/svg` namespace *(in code)* | `Renderers/SVGRenderer.swift` |
| **HTML Living Standard — Canvas 2D context** (WHATWG) | The Canvas drawing-command export (`bezierCurveTo`, etc.) *(in code)* | `Renderers/CanvasRenderer.swift` |
| **IEC 61966-2-1 — sRGB** | The default device colour space *(in code: `CGColorSpace.sRGB`)* | `Core/ColorSpace.swift` |
| **Adobe TN #5176 — Compact Font Format (CFF)** & the **OpenType** spec | Glyph-outline parsing for vector text *(in code: "PostScript-outlined OpenType")* | `Core/CFFFont.swift`, `Core/Font.swift` |

---

## Algorithms implemented from the literature

Standard results the engine implements directly; cited so a reader can find the
derivation.

| Source | Informs | File |
|---|---|---|
| **The cubic-Bézier circle approximation**, constant κ = 4⁄3 (√2 − 1) = 0.5522847498… | Circular rounded-rect and ellipse corners *(in code: `let kappa = 0.5522847498307933`)* | `Core/Path.swift` (`addRoundedRect`, `addEllipse`) |
| **De Casteljau's algorithm** (Paul de Casteljau, 1959) / **Bézier** (Pierre Bézier) curve subdivision | Flattening cubic/quadratic curves to line segments for rasterization; first-derivative extrema for bounding boxes *(in code)* | `Core/Path.swift`, `Core/Geometry+BoundingBox.swift` |
| **Scanline polygon fill with coverage antialiasing** (Foley, van Dam, Feiner & Hughes, *Computer Graphics: Principles and Practice*) | The sub-row + analytic-horizontal coverage rasterizer; the non-zero-winding and even-odd fill rules | `Renderers/CoverageRasterizer.swift`, `Core/FillRule.swift` |
| **Porter, T. & Duff, T., "Compositing Digital Images," SIGGRAPH 1984** | The Porter-Duff compositing operators and source-over blending *(in code: "Porter-Duff compositing operators")* | `Core/BlendMode.swift`, the rasterizers |
| **Projective geometry / image warping** (Paul Heckbert, *Fundamentals of Texture Mapping and Image Warping*, 1989) | The 3×3 homography mapping a rectangle to four points; homogeneous `w`-divide; perspective texture mapping | `Geometry/ProjectiveTransform.swift`, `Renderers/ProjectiveImageRasterizer.swift` |
| **Affine transform matrices** (standard 2D linear algebra; the Quartz CTM model) | Translation/scale/rotation/skew, concatenation order, inversion | `Geometry/AffineTransform.swift` |

---

## Articles & reverse-engineering

| Source | Informs | File |
|---|---|---|
| **Liam Rosenfeld, "My Quest for the Apple Icon Shape"** — https://liamrosenfeld.com/posts/apple_icon_quest/ | The exact fixed-ratio control-point constants for Apple's *continuous* (squircle) corner, inverse-mapped from `UIBezierPath` *(in code, with the constants `1.52866498` and the `(u, v)` ratios)* | `Core/Path.swift` (`addContinuousRoundedRect`) |
| **Figma, "Desperately Seeking Squircles"** — https://www.figma.com/blog/desperately-seeking-squircles/ | Background on continuous-corner smoothing and how it degrades at the capsule limit *(in code)* | `Core/Path.swift` |

> The squircle corner is explicitly **not** a superellipse — the source notes a
> superellipse fits Apple's corner worse than a plain circle. See
> `docs/lessons/lesson12_squircle.md`.

---

## The imaging model (books)

| Source | Informs |
|---|---|
| **David Gelphman & Bunny Laden, *Programming with Quartz* (Morgan Kaufmann, 2005)** | The whole Core-Graphics imaging model PureDraw mirrors: the graphics-state stack, the CTM, clipping as a frozen graphics-state region, the painter's model, transformations. Cited by section throughout `docs/lessons/`. Local copy in `PureDrawResearch/CG/`. |
| **Gelphman & Laden, *Quartz 2D Graphics for Mac OS X Developers*** | Companion treatment of transformations and the imaging model. |
| **Apple, Core Graphics / Quartz 2D documentation** (`CGPath`, `CGContext`, `CGColorSpace`, `CGAffineTransform`) | API-parity reference: PureDraw's surface mirrors `CGContext` so a caller can move between them. Consulted via the Cupertino documentation tooling. |

### Supplementary (vendor-neutral CG theory)

> **Apple's books are the canon** for how Core Graphics / Core Animation *behave*. These
> texts are supplements only — for the framework-independent math (homogeneous coordinates,
> projection, texture mapping, rasterization) behind the engine, never for Apple-specific
> behaviour or as a comparison stack.

| Source | Informs |
|---|---|
| **David J. Eck, *Introduction to Computer Graphics*, v1.4 (2023)** — math.hws.edu/graphicsbook, CC BY-NC-SA | Background on the general-CG math the engine implements: 2D/3D transforms and homogeneous coordinates, projection, the projective/perspective texture-mapping pipeline (complements Heckbert for `ProjectiveTransform`/`ProjectiveImageRasterizer`), and scanline rasterization. Local copy `PureDrawResearch/CG/graphicsbook-linked.pdf`. |

---

## How to extend this file

When code adopts an external result — a spec, a paper, an algorithm, a reverse-engineered
constant — add a row here and, where it is a single value or a non-obvious method, cite the
source *in the code comment too*. The standard is that no constant or wire-format detail is
unexplained: a reader should be able to trace every magic number to its origin.
