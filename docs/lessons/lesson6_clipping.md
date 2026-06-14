# Lesson 6: Clipping Boundaries

Clipping restricts subsequent drawing operations to a specific geometric shape. Master mathematical intersection bounds and winding rules to create masking paths.

---

## 1. Core Concepts

### Restricting the Active Canvas
Clipping does not modify the geometries you draw. Instead, it defines a stencil (or mask) over the canvas. Any drawing commands issued while a clip is active will only paint pixels that lie inside the stencil boundaries.

### Shrinking Operations Only
A clipping path can only **restrict** the active area. Concatenating a new clipping path intersects it with the existing clip. There is no vector operation to "add" area to a clip or "unclip" once a region is discarded. To recover the full canvas, you must save the graphics state before clipping and restore it afterward.

---

## 2. Mathematical Foundations

### Path Intersections
If the current clipping region is $A$, and you clip to a path $B$, the new clipping region is the intersection:

$$\text{Clip}_{\text{new}} = A \cap B$$

Because $A \cap B \subseteq A$, the drawable area can only shrink or remain equal, never grow:

$$\text{Area}(\text{Clip}_{\text{new}}) \le \text{Area}(\text{Clip}_{\text{old}})$$

### Fill Rules
When a path is self-intersecting or contains nested subpaths, graphics engines use one of two mathematical algorithms to decide which regions are "inside" the path (and thus clipped to) and which are "outside".

To determine if a point $P$ is inside a path:
1.  Draw a ray from $P$ extending in any direction to infinity.
2.  Count the intersections between the ray and the path segments.

#### 1. Non-Zero Winding Rule
Track the direction of the path segments relative to the ray. Start a counter at $0$:
*   Add $+1$ each time a segment crosses the ray from left to right.
*   Subtract $-1$ each time a segment crosses from right to left.

If the final winding number $W \ne 0$, the point is **inside** the path. If $W = 0$, the point is **outside**.

#### 2. Even-Odd Rule
Count the total number of segment crossings. Winding direction is ignored:
*   If the crossing count is **odd**, the point is **inside**.
*   If the crossing count is **even**, the point is **outside**.

```
Nested Circles (donut):
- Non-Zero Winding (same direction): Center is inside (W = 2)
- Even-Odd: Center is outside (Count = 2, Even)
```

---

## 3. Code Demonstration

The following Swift code creates a circular donut clip using the Even-Odd rule and draws nested patterns inside it.

```swift
import Core
import Geometry
import Renderers

func drawClippingDemo() {
    var context = GraphicsContext()
    let size: Double = 300
    
    // Fill background with grey
    context.setFillColor(Color(r: 0.2, g: 0.2, b: 0.2, a: 1.0))
    context.fill(Rect(x: 0, y: 0, width: size, height: size))
    
    // Save state before applying the clip
    context.saveGState()
    
    // Create a path containing two nested circles to form a donut
    var donut = Path()
    // Outer circle
    donut.addEllipse(in: Rect(x: 30, y: 30, width: 240, height: 240))
    // Inner circle
    donut.addEllipse(in: Rect(x: 80, y: 80, width: 140, height: 140))
    
    // Clip using Even-Odd to make the center hollow
    context.addPath(donut)
    context.clip(using: .evenOdd)
    
    // Draw grid lines; they will only show inside the donut ring
    context.setStrokeColor(Color(r: 0.2, g: 0.8, b: 0.9, a: 1.0))
    context.setLineWidth(2.0)
    for x in stride(from: 0.0, through: size, by: 15.0) {
        context.move(to: Point(x: x, y: 0))
        context.addLine(to: Point(x: x, y: size))
        context.strokePath()
    }
    
    // Restore state to clear the clipping path
    context.restoreGState()
    
    // Draw an unclipped red border circle to prove the clip was removed
    context.setStrokeColor(Color(r: 0.9, g: 0.3, b: 0.3, a: 1.0))
    context.setLineWidth(4.0)
    context.strokeEllipse(in: Rect(x: 20, y: 20, width: 260, height: 260))
    
    // Render to output
    let renderer = SVGRenderer(width: size, height: size)
    do {
        let svg = try renderer.draw(context)
        print("Clipping SVG:\n\(svg)")
    } catch {
        print("Error: \(error)")
    }
}
```

---

## 4. Exercises

1.  **Donut Analysis**: Draw a ray from the center of a nested donut path (consisting of two concentric circles). Calculate the crossing count and winding number if:
    *   **Case A**: Both circles were drawn in a clockwise direction.
    *   **Case B**: The outer circle was drawn clockwise, and the inner circle counter-clockwise.
    *   State the fill results under both the Non-Zero Winding and Even-Odd rules.
2.  **Unclip Verification**: Write a Swift routine that creates three nested rectangular clips, demonstrating that you can jump back to intermediate clipping bounds by pairing `saveGState()` and `restoreGState()` correctly.
