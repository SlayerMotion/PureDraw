# Lesson 11: Antialiasing & Coverage Rasterization

A vector path is a continuous mathematical shape; a raster image is a finite grid of
square pixels. Antialiasing is the bridge: instead of asking "is this pixel inside the
shape — yes or no?", it asks "what *fraction* of this pixel does the shape cover?" and
uses that fraction as the pixel's opacity. This lesson covers how `PureDraw` turns a
filled path into per-pixel coverage.

---

## 1. Core Concepts

### Aliasing: the staircase
If you test only the **center** of each pixel — inside the shape paint it fully, outside
leave it blank — a slanted or curved edge becomes a hard staircase of fully-on and
fully-off pixels. This is *aliasing*: the sharp binary decision throws away all the
sub-pixel detail of where the true edge sits.

### Coverage: the gray edge
The fix is to compute **fractional coverage**: a pixel the edge cuts in half gets 0.5
coverage, drawn at 50% opacity. Along an edge, coverage ramps smoothly from 1 (fully
inside) through fractional values to 0 (fully outside), so the staircase becomes a soft,
correctly-weighted gradient that the eye reads as a clean line.

### The hybrid strategy
Computing the exact area of a pixel inside an arbitrary curved path is expensive.
`CoverageRasterizer` uses a practical hybrid that is exact in one axis and supersampled in
the other:

* **Vertically**: each pixel row is split into `subsampleRows = 4` sub-rows. The shape is
  scanned at the center of each sub-row.
* **Horizontally**: within each sub-row, coverage is computed **analytically** — the exact
  fractional overlap of each inside-span with each pixel column.

Four vertical samples × exact horizontal coverage is far cheaper than a full 4×4 grid and
visually almost identical, because the analytic horizontal term already captures most of
the edge detail.

---

## 2. Mathematical Foundations

### Scanline span detection
For a sub-row at height $y$, find every point where the path's edges cross $y$. Sort the
crossings by $x$. Walking them left to right toggles an **inside/outside** state according
to the fill rule (see Lesson 6): non-zero winding accumulates edge direction
$\sum d_i \neq 0$; even-odd toggles parity. Each maximal inside interval is a **span**
$[x_0, x_1]$.

### Analytic horizontal coverage
A span $[x_0, x_1]$ contributes to pixel column $p$ (covering $[p, p+1]$) the length of
their intersection:

$$\text{overlap}(p) = \max\!\big(0,\; \min(p+1, x_1) - \max(p, x_0)\big)$$

This is a number in $[0, 1]$: a fully-covered column gets 1, a column the span clips gets
the exact fraction.

### Accumulation across sub-rows
Each sub-row carries weight $w = 1/N$ with $N = 4$. The final coverage of pixel $(p, y)$
sums the weighted horizontal overlaps of every sub-row, clamped to 1:

$$C(p) = \min\!\left(1,\; \sum_{s=0}^{N-1} \frac{1}{N}\, \text{overlap}_s(p)\right)$$

So the vertical detail comes from the 4 discrete samples and the horizontal detail is
exact. A pixel a near-vertical edge cuts at $x_0 = p + 0.3$ gets $C \approx 0.7$; a pixel a
near-horizontal edge crosses between sub-rows 2 and 3 gets $C \approx 0.5$.

### Compositing the coverage
Coverage is the **alpha** the fill is blended with. Blending happens in *premultiplied*
form to stay correct over a transparent background: the source contribution is
$(\text{color} \times C)$, composited source-over onto the destination. (The aliased path
— `antialiased = false` — skips all of this and uses the pixel-center rule: column $p$ is
on iff $x_0 \le p + 0.5 < x_1$.)

---

## 3. Code Demonstration

Fill a triangle and read back the alpha along a slanted edge: interior pixels are fully
opaque, exterior fully transparent, and the edge carries a ramp of partial-coverage values
— the antialiasing made visible as numbers.

```swift
import Core
import Geometry
import Renderers

func inspectAntialiasedEdge() throws {
    var context = GraphicsContext()
    context.setFillColor(Color(r: 0.1, g: 0.5, b: 0.9, a: 1.0))

    // A triangle with a slanted right edge through the canvas.
    var path = Path()
    path.move(to: Point(x: 4, y: 4))
    path.addLine(to: Point(x: 44, y: 24))   // slanted edge
    path.addLine(to: Point(x: 4, y: 44))
    path.closeSubpath()
    context.fill(path)

    let image = try BitmapRenderer(width: 48, height: 48).draw(context)

    // Read the alpha channel across row y = 24, crossing the slanted edge.
    func alpha(_ x: Int, _ y: Int) -> UInt8 { image.data[(y * 48 + x) * 4 + 3] }
    for x in 40 ... 46 {
        print("x=\(x) alpha=\(alpha(x, 24))")   // 255 … partial … 0
    }
}
```

The printed alphas step down through intermediate values (e.g. `255, 255, 180, 90, 12, 0`)
rather than snapping `255` straight to `0`. Those in-between bytes are the fractional
coverage $C(p)$.

---

## 4. Exercises

1. **Sub-row count.** `subsampleRows` is 4. Predict what a near-horizontal edge looks like
   if it drops to 1 (aliased) and to 16. Why does increasing it help vertical edges far
   less than horizontal ones? (Hint: the horizontal term is already exact.)
2. **Conservation.** Prove that for any single span $[x_0, x_1]$ within one sub-row,
   $\sum_p \text{overlap}(p) = x_1 - x_0$. Why does this mean a thin sliver never
   "loses" or "gains" ink, only spreads it?
3. **Premultiplied blending.** A 50%-coverage blue pixel is composited onto a transparent
   background, then that result onto white. Show why doing the blend in premultiplied alpha
   gives a different (and correct) result versus blending the straight (non-premultiplied)
   color twice.
