# Lesson 1: The Native Coordinate Space

In 2D vector graphics, all shapes are described by geometric primitives defined in a coordinate space. Master the distinction between mathematical vector space and physical display raster grids before manipulating drawing operations.

---

## 1. Core Concepts

### Vector Graphics vs. Raster Images
Vector graphics define shapes through mathematical equations (lines, curves, and polygons) relative to an coordinate space. Raster graphics represent images as a fixed grid of color values (pixels). Vector descriptions remain infinitely scalable and resolution-independent because the rasterization step occurs at the final rendering stage based on the target device's pixel density.

### Coordinate Space Origins
Different graphics APIs place the coordinate origin at different locations:
*   **Mathematical Cartesian Coordinate Space**: The origin $(0, 0)$ is at the bottom-left corner. Coordinates extend infinitely to the right ($+x$) and upwards ($+y$). This is the native coordinate system of Core Graphics (Quartz 2D) and `PureDraw`.
*   **Window/Screen Space**: The origin $(0, 0)$ is at the top-left corner. Coordinates extend to the right ($+x$) and downwards ($+y$). This is the standard coordinate system for UIKit, AppKit (views), and the DOM (HTML Canvas).

Mixing these spaces without explicit projection transforms leads to inverted vertical rendering.

---

## 2. Mathematical Foundations

### Device Pixels vs. User Space Points
Quartz 2D uses a scale-independent coordinate system called **user space**. Physical output devices operate in **device space** (measured in pixels). The relationship between the two is defined by the scale factor:

$$\text{Device Pixels} = \text{User Points} \times \text{Scale Factor}$$

For example, on a 3x Retina display, a $10 \times 10$ point rectangle occupies a $30 \times 30$ grid of physical device pixels.

### The Flipping Transform
To map a point $(x_{\text{user}}, y_{\text{user}})$ from a bottom-left Cartesian coordinate system to a top-left device system of viewport height $H$ (in points), apply the following transformation:

$$x_{\text{device}} = x_{\text{user}}$$
$$y_{\text{device}} = H - y_{\text{user}}$$

When converting matrices, this corresponds to applying a translation followed by a scale reversal:

$$\begin{bmatrix} x_{\text{device}} \\ y_{\text{device}} \\ 1 \end{bmatrix} = \begin{bmatrix} 1 & 0 & 0 \\ 0 & -1 & H \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} x_{\text{user}} \\ y_{\text{user}} \\ 1 \end{bmatrix}$$

This matrix operation translates the vertical axis by the viewport height and scales the vertical axis by $-1$.

---

## 3. Code Demonstration

The following Swift example demonstrates how to initialize a `GraphicsContext`, define coordinates in the native bottom-left Cartesian space, draw a shape, and render it to a vector SVG string using the `SVGRenderer`.

```swift
import Core
import Geometry
import Renderers

func drawCoordinateDemo() {
    // 1. Instantiate the stateful graphics context
    var context = GraphicsContext()
    
    // 2. Define drawing bounds in user points
    let canvasWidth: Double = 400
    let canvasHeight: Double = 400
    let margin: Double = 40
    
    // Set fill and stroke colors
    context.setFillColor(Color(r: 0.1, g: 0.1, b: 0.1, a: 1.0)) // Dark background
    context.setStrokeColor(Color(r: 0.9, g: 0.9, b: 0.9, a: 1.0)) // Light lines
    context.setLineWidth(2.0)
    
    // Fill the canvas background
    let backgroundRect = Rect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
    context.fill(backgroundRect)
    
    // 3. Construct coordinate axes
    // X-Axis (Bottom margin line)
    context.move(to: Point(x: margin, y: margin))
    context.addLine(to: Point(x: canvasWidth - margin, y: margin))
    
    // Y-Axis (Left margin line)
    context.move(to: Point(x: margin, y: margin))
    context.addLine(to: Point(x: margin, y: canvasHeight - margin))
    context.strokePath()
    
    // 4. Draw a data point at user coordinates (100, 200)
    let pointX: Double = 100
    let pointY: Double = 200
    
    // Set stroke and fill properties for the point marker
    context.setFillColor(Color(r: 0.9, g: 0.3, b: 0.3, a: 1.0)) // Red marker
    let markerRadius: Double = 6.0
    let markerRect = Rect(
        x: pointX - markerRadius,
        y: pointY - markerRadius,
        width: markerRadius * 2,
        height: markerRadius * 2
    )
    context.fillEllipse(in: markerRect)
    
    // 5. Render the context output to SVG
    let renderer = SVGRenderer(width: canvasWidth, height: canvasHeight)
    do {
        let svgString = try renderer.draw(context)
        print("Generated SVG:\n\(svgString)")
    } catch {
        print("Rendering failed: \(error)")
    }
}
```

---

## 4. Exercises

1.  **Manual Conversion**: Given a target canvas of size $800 \times 600$ points and a retina scale of $2.0$, calculate the physical device pixel coordinates for the user space point $(150, 450)$ under a native bottom-left system.
2.  **Origin Translation**: Write a helper function in Swift that accepts a `GraphicsContext`, a point in top-left user space, and the viewport height, and returns the converted `Point` in bottom-left user space.
