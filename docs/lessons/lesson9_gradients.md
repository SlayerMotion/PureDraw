# Lesson 9: Gradients & Patterns

Vector graphics support complex fills like linear/radial gradients and repeating patterns. Master color interpolation geometry and grid-coordinate tiling to create rich texturing.

---

## 1. Core Concepts

### Gradients as Color Fields
A gradient defines a continuous field of color values across a region. Instead of painting a solid color, the rendering engine computes a parametric value $t \in [0, 1]$ for each pixel, matches it against defined color stops, and interpolates the final color.

### Pattern Fills
A pattern fill repeats a small vector drawing (a pattern cell) infinitely across the canvas in a grid pattern. The pattern grid has its own transform matrix, isolating its rotation and scaling from the shapes being filled.

---

## 2. Mathematical Foundations

### Linear Gradient Interpolation
A linear gradient is defined by a start point $\mathbf{P}_0 = (x_0, y_0)$ and an end point $\mathbf{P}_1 = (x_1, y_1)$. To find the color of an arbitrary canvas pixel $\mathbf{P} = (x, y)$, project $\mathbf{P}$ onto the gradient axis vector $\mathbf{V} = \mathbf{P}_1 - \mathbf{P}_0$:

$$t = \frac{(\mathbf{P} - \mathbf{P}_0) \cdot (\mathbf{P}_1 - \mathbf{P}_0)}{\|\mathbf{P}_1 - \mathbf{P}_0\|^2}$$

Expanding this dot product yields:

$$t = \frac{(x - x_0)(x_1 - x_0) + (y - y_0)(y_1 - y_0)}{(x_1 - x_0)^2 + (y_1 - y_0)^2}$$

*   If $t \le 0$: The color defaults to the start color (or extends).
*   If $t \ge 1$: The color defaults to the end color (or extends).
*   If $0 < t < 1$: The color is interpolated between the two closest stops:

$$C(t) = (1 - u) \cdot C_a + u \cdot C_b, \quad \text{where } u = \frac{t - t_a}{t_b - t_a}$$

### Radial Gradient Interpolation
A radial gradient is defined by a start circle centered at $\mathbf{C}_0$ with radius $r_0$ and an end circle at $\mathbf{C}_1$ with radius $r_1$. The color parameter $t$ is calculated by solving a quadratic equation representing the intersection of a ray from the pixel through the cone formed by the two circles.

### Pattern Grid Tiling
To draw a pattern cell of width $W$ and height $H$ at canvas pixel $(x, y)$, map the pixel coordinates into cell coordinates using the modulo operator:

$$x_{\text{cell}} = x \pmod W$$
$$y_{\text{cell}} = y \pmod H$$

This maps all canvas coordinates to a coordinate bounded within the cell limits $[0, W] \times [0, H]$.

---

## 3. Code Demonstration

The following Swift code creates a metallic finish using a multi-stop linear gradient and draws a grid-tiled pattern.

```swift
import Core
import Geometry
import Renderers

func drawGradientsAndPatternsDemo() {
    var context = GraphicsContext()
    let size: Double = 300
    
    // 1. Create a multi-stop metallic gradient (Silver effect)
    let stops = [
        GradientStop(location: 0.0, color: Color(r: 0.8, g: 0.8, b: 0.8, a: 1.0)),
        GradientStop(location: 0.3, color: Color(r: 0.95, g: 0.95, b: 0.95, a: 1.0)),
        GradientStop(location: 0.5, color: Color(r: 0.5, g: 0.5, b: 0.5, a: 1.0)),
        GradientStop(location: 0.7, color: Color(r: 0.9, g: 0.9, b: 0.9, a: 1.0)),
        GradientStop(location: 1.0, color: Color(r: 0.7, g: 0.7, b: 0.7, a: 1.0))
    ]
    let silverGradient = Gradient(stops: stops)
    
    // Fill background with the silver gradient (clipped to canvas bounds)
    context.saveGState()
    context.addRect(Rect(x: 20, y: 20, width: 260, height: 260))
    context.clip()
    context.drawLinearGradient(
        silverGradient,
        start: Point(x: 20, y: 20),
        end: Point(x: 280, y: 280),
        options: []
    )
    context.restoreGState()
    
    // 2. Define a diagonal pattern cell
    var patternCellContext = GraphicsContext()
    patternCellContext.setStrokeColor(Color(r: 0.2, g: 0.2, b: 0.2, a: 0.3))
    patternCellContext.setLineWidth(1.0)
    patternCellContext.move(to: Point(x: 0, y: 0))
    patternCellContext.addLine(to: Point(x: 10, y: 10))
    patternCellContext.strokePath()
    
    let gridPattern = Pattern(
        bounds: Rect(x: 0, y: 0, width: 10, height: 10),
        commands: patternCellContext.commands
    )
    
    // Fill a circle in the center with the pattern overlay
    context.saveGState()
    context.setFillPattern(gridPattern)
    context.fillEllipse(in: Rect(x: 80, y: 80, width: 140, height: 140))
    context.restoreGState()
    
    // Render output
    let renderer = SVGRenderer(width: size, height: size)
    do {
        let svg = try renderer.draw(context)
        print("Gradient Pattern SVG:\n\(svg)")
    } catch {
        print("Error: \(error)")
    }
}
```

---

## 4. Exercises

1.  **Linear Gradient Projection**: A linear gradient starts at $\mathbf{P}_0 = (0, 10)$ and ends at $\mathbf{P}_1 = (0, 90)$. Calculate the value of the interpolation parameter $t$ at pixel location $\mathbf{P} = (75, 50)$.
2.  **Radial Distance**: A radial gradient has its start circle center at $(0, 0)$ with radius $0.0$, and its end circle center at $(0, 0)$ with radius $100.0$. Find the interpolation parameter $t$ for any point $(x, y)$ that lies on the circle $x^2 + y^2 = 2500$.
