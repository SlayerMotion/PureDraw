# Lesson 4: Bezier Curves & Curve Subdivision

Bézier curves define smooth vector shapes through control points. Master the parametric mathematics of curves and understand how the rasterizer subdivides curves into discrete line segments.

---

## 1. Core Concepts

### Parametric Curves
Unlike explicit functions like $y = f(x)$, curves in 2D graphics are defined parametrically. Both $x$ and $y$ are calculated as functions of a single parameter $t$, which ranges from $0.0$ (start of the curve) to $1.0$ (end of the curve):

$$\mathbf{P}(t) = (x(t), y(t)), \quad t \in [0, 1]$$

This allows curves to loop, overlap, and have vertical tangents, which is impossible with standard Cartesian functions.

### Control Points
A Bézier curve is anchored by its start and end points (anchors) and guided by its control points. The control points act like gravity wells, pulling the path toward them without the path necessarily intersecting them.

---

## 2. Mathematical Foundations

### Quadratic Bézier Curves
A quadratic Bézier curve is defined by three points: start $P_0$, control $P_1$, and end $P_2$. The curve equation is:

$$\mathbf{B}(t) = (1-t)^2 P_0 + 2(1-t)t P_1 + t^2 P_2$$

This is a linear interpolation of linear interpolations.

### Cubic Bézier Curves
A cubic Bézier curve is defined by four points: start $P_0$, first control $P_1$, second control $P_2$, and end $P_3$. The curve equation is:

$$\mathbf{B}(t) = (1-t)^3 P_0 + 3(1-t)^2 t P_1 + 3(1-t)t^2 P_2 + t^3 P_3$$

Most design vector applications (and font glyph definitions) use cubic curves because they allow for inflection points (S-shapes).

```
        P1 *--------* P2
          /          \
         /            \
   P0   *              * P3
```

### De Casteljau's Algorithm & Flatness
A GPU or rasterizer cannot draw a continuous mathematical curve directly; it can only draw straight lines or pixels. The engine converts curves to lines using **subdivision** via De Casteljau's algorithm:
1.  Compute the midpoints of the control polygon lines.
2.  Connect these midpoints and find the midpoints of the connecting lines.
3.  Repeat until a single midpoint lies on the curve at $t = 0.5$.
4.  This point splits the curve into two halves (left and right), each with its own control polygon.

The division continues recursively until the curve segment is **flat** within a threshold called **flatness** ($F$):

$$\text{Distance}(\text{Control Points}, \text{Chord Line}) \le F$$

If a segment's deviation from the straight chord is less than the flatness threshold, the segment is drawn as a straight line. Lower flatness values produce smoother curves at the cost of more line segments and higher CPU/GPU overhead.

---

## 3. Code Demonstration

The following Swift example constructs a smooth vector heart shape using cubic Bézier curves and renders it under two different flatness settings.

```swift
import Core
import Geometry
import Renderers

func drawCurveFlatnessDemo() {
    var context = GraphicsContext()
    
    // Draw background
    context.setFillColor(Color(r: 0.1, g: 0.1, b: 0.1, a: 1.0))
    context.fill(Rect(x: 0, y: 0, width: 500, height: 250))
    
    // Define a heart path
    var heart = Path()
    heart.move(to: Point(x: 100, y: 50))
    // Left lobe
    heart.addCurve(to: Point(x: 50, y: 150), control1: Point(x: 10, y: 100), control2: Point(x: 10, y: 150))
    heart.addCurve(to: Point(x: 100, y: 200), control1: Point(x: 50, y: 150), control2: Point(x: 75, y: 180))
    // Right lobe
    heart.addCurve(to: Point(x: 150, y: 150), control1: Point(x: 125, y: 180), control2: Point(x: 150, y: 150))
    heart.addCurve(to: Point(x: 100, y: 50), control1: Point(x: 190, y: 150), control2: Point(x: 190, y: 100))
    heart.closeSubpath()
    
    // Draw 1: Left side with low flatness (very smooth, high subdivision)
    context.saveGState()
    context.translate(by: 50.0, 0.0)
    context.setStrokeColor(Color(r: 0.2, g: 0.9, b: 0.2, a: 1.0)) // Green
    context.setLineWidth(3.0)
    context.setFlatness(0.1) // Sub-pixel resolution
    context.stroke(heart)
    context.restoreGState()
    
    // Draw 2: Right side with high flatness (blocky, low subdivision)
    context.saveGState()
    context.translate(by: 250.0, 0.0)
    context.setStrokeColor(Color(r: 0.9, g: 0.2, b: 0.2, a: 1.0)) // Red
    context.setLineWidth(3.0)
    context.setFlatness(15.0) // Large flat tolerance (shows line segments)
    context.stroke(heart)
    context.restoreGState()
    
    // Render
    let renderer = SVGRenderer(width: 500, height: 250)
    do {
        let svg = try renderer.draw(context)
        print("Heart Curves SVG:\n\(svg)")
    } catch {
        print("Rendering error: \(error)")
    }
}
```

---

## 4. Exercises

1.  **Midpoint Calculation**: A cubic Bézier curve starts at $P_0(0, 0)$, ends at $P_3(100, 100)$, and has control points $P_1(0, 100)$ and $P_2(100, 0)$. Calculate the coordinates of the curve at $t = 0.5$ using the parametric equation.
2.  **Flatness Analysis**: If a drawing is scaled up by a factor of $5$ using a scale transform, what must happen to the flatness parameter in user space to maintain the same pixel-level smoothness on screen?
