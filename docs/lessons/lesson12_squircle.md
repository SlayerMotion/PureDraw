# Lesson 12: Continuous Corners, the Squircle (and Why It Is *Not* a Superellipse)

Every modern Apple UI surface, the app icon, the button, the sheet, the home-screen
grid, uses a rounded corner that is subtly *smoother* than a circular arc. It is widely
called a "superellipse" or "squircle". This lesson builds the real corner `PureDraw` draws,
and corrects a popular myth: Apple's corner is **not** a superellipse.

---

## 1. Core Concepts

### Curvature continuity, not just position continuity
A plain rounded rectangle joins a straight edge to a circular arc. At the junction the
*position* is continuous but the **curvature** is not: the edge has curvature $0$, the arc
has curvature $1/r$, and the value jumps instantly. The eye reads that jump as a slightly
abrupt, "tight" corner.

A **continuous** corner ramps curvature smoothly from $0$ on the edge up to a maximum and
back, so there is no visible junction. The rounded region also reaches *further* along each
edge than a circular corner of the same nominal radius.

### The superellipse myth
A superellipse is the curve $\left|\frac{x}{a}\right|^{n} + \left|\frac{y}{b}\right|^{n} = 1$.
For $n = 2$ it is an ellipse; for $n \approx 4$–$5$ it looks squircle-ish. It is the
*intuitive* explanation, and it is wrong for Apple's shape. Apple's actual corner is a
**fixed-ratio cubic Bézier** construction, reverse-engineered from `UIBezierPath`. A
superellipse fits Apple's corner *worse than a plain circle does*. `PureDraw` implements the
real Bézier corner, not a superellipse, and this lesson treats the myth as the teaching
hook: the famous name is a misnomer.

### Two corner styles
* **Circular** (`addRoundedRect`): a quarter-circle arc per corner, approximated by one
  cubic Bézier using the classic circle constant.
* **Continuous** (`addContinuousRoundedRect`): Apple's squircle, three cubic Béziers per
  corner with fixed dimensionless control-point ratios.

---

## 2. Mathematical Foundations

### The circular corner and the magic constant
A quarter circle of radius $r$ cannot be drawn exactly with a cubic Bézier, but it can be
approximated to within ~0.02% by pulling each control point a fixed fraction of $r$ along
the tangent:

$$\kappa = \frac{4}{3}\left(\sqrt{2} - 1\right) = 0.5522847498\ldots$$

`PureDraw` uses exactly this $\kappa = 0.5522847498307933$ for circular rounding. A corner
control point sits at distance $\kappa r$ from the arc endpoint along the edge tangent.

### The continuous corner: fixed-ratio Béziers
The squircle corner is built from **three** cubic Bézier segments whose control points are
fixed ratios of the corner scale $r$, extracted by inverse-mapping `UIBezierPath`'s output
(Liam Rosenfeld, *"My Quest for the Apple Icon Shape"*). Two constants define it:

* **Edge consumption ratio** $\rho = 1.52866498$. The corner eats $\rho \cdot r$ of length
  along *each* edge, about 53% further than a circular corner ($\rho > 1$), which is why a
  squircle looks rounder for the same radius.
* The interior control points are dimensionless $(u, v)$ pairs (e.g.
  $(1.0884, 0)$, $(0.8684, 0)$, $(0.6315, 0.0749)$, …) applied along the two edge axes.

Each corner is therefore:

$$P(u, v) = \text{vertex} + r\,\big(u\,\hat{\mathbf{a}}_{\text{in}} + v\,\hat{\mathbf{a}}_{\text{out}}\big)$$

where $\hat{\mathbf{a}}_{\text{in}}$ and $\hat{\mathbf{a}}_{\text{out}}$ are unit vectors
along the incoming and outgoing edges. Three `addCurve` calls per corner trace the smooth
ramp-in, the rounded apex, and the ramp-out.

### Degrading at the capsule limit
The consumption $\rho r$ is clamped to half the shorter side so adjacent corners never
overlap:

$$\text{consumption} = \min\!\big(\rho\, |r|,\; \tfrac{1}{2}\min(w, h)\big)$$

When the radius is large enough that $\rho r$ would exceed half the side, the corner is
*scaled down to meet its neighbour exactly*, producing a smooth capsule that preserves
continuous curvature, rather than snapping back to a circular arc. (Apple's exact
near-capsule corner is proprietary and unspecified; this is a faithful, continuous
approximation.)

---

## 3. Code Demonstration

Draw the same rectangle with both corner styles and compare. The continuous corners visibly
extend further along the edges.

```swift
import Core
import Geometry
import Renderers

func compareCorners() throws {
    var context = GraphicsContext()
    let rect = Rect(x: 20, y: 20, width: 160, height: 160)
    let radius = 48.0

    // Circular rounding (quarter-circle arcs).
    var circular = Path()
    circular.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
    context.setFillColor(Color(r: 0.85, g: 0.3, b: 0.3, a: 1.0))
    context.fill(circular)

    // Apple's continuous corners (the squircle), three Béziers per corner.
    var squircle = Path()
    squircle.addContinuousRoundedRect(in: rect.offsetBy(dx: 180, dy: 0), cornerRadius: radius)
    context.setFillColor(Color(r: 0.3, g: 0.5, b: 0.85, a: 1.0))
    context.fill(squircle)

    let svg = try SVGRenderer(width: 380, height: 200).draw(context)
    print(svg)
}
```

Overlay the two and the squircle's outline sits *outside* the circle near the straight
edges and *inside* it near the diagonal, the signature of continuous curvature.

---

## 4. Exercises

1. **Derive $\kappa$.** Show that a single cubic Bézier matching a quarter circle's
   endpoints and tangents, with control-point distance $\kappa r$, gives
   $\kappa = \frac{4}{3}(\sqrt{2}-1)$ by forcing the curve through the arc's midpoint
   $(\frac{r}{\sqrt2}, \frac{r}{\sqrt2})$.
2. **Disprove the superellipse.** Pick $n$ so a superellipse has the same edge consumption
   $\rho r$ as the continuous corner, then compare its midpoint curvature to the Bézier
   corner's. Why can no single $n$ match both the extent and the curvature profile?
3. **Capsule.** For a $100 \times 60$ rect, find the radius at which the continuous corners
   first meet (the capsule limit). What does `addContinuousRoundedRect` draw for any larger
   radius?
