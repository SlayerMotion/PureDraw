# Lesson 5: The Current Transformation Matrix (CTM)

The Current Transformation Matrix (CTM) defines the mapping between user space coordinates and device space pixels. Master 3x3 affine transformations to manipulate coordinates instead of rewriting shape geometry.

---

## 1. Core Concepts

### Affine Transformations
An affine transform maps points to new points while preserving collinearity (points on a line remain on a line) and ratios of distances (the midpoint of a segment remains the midpoint). Affine transformations include translation, scaling, rotation, and shearing.

### The CTM as a Coordinate Grid
Instead of thinking of transformations as "moving the shapes", it is mathematically cleaner to think of them as **moving the coordinate grid**. When you scale the context by $2.0$, you are doubling the size of the coordinate grid's units. When you rotate the context, you are rotating the grid lines themselves.

---

## 2. Mathematical Foundations

### Homogeneous Coordinates
A standard 2D translation cannot be expressed as a $2 \times 2$ matrix multiplication because it requires an addition:

$$\begin{bmatrix} x' \\ y' \end{bmatrix} = \begin{bmatrix} x \\ y \end{bmatrix} + \begin{bmatrix} t_x \\ t_y \end{bmatrix}$$

To combine translation, scale, and rotation into a single unified matrix operation, we use **homogeneous coordinates** by adding a dummy coordinate $w = 1$:

$$\begin{bmatrix} x \\ y \end{bmatrix} \to \begin{bmatrix} x \\ y \\ 1 \end{bmatrix}$$

### The Affine Transformation Matrix
An affine transformation is represented by a $3 \times 3$ matrix:

$$\begin{bmatrix} x' \\ y' \\ 1 \end{bmatrix} = \begin{bmatrix} a & c & t_x \\ b & d & t_y \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} x \\ y \\ 1 \end{bmatrix}$$

Multiplying out the equations yields:

$$x' = a x + c y + t_x$$
$$y' = b x + d y + t_y$$

*   **Translation**: $a=1, d=1, c=0, b=0$. Point shifts by $(t_x, t_y)$.
*   **Scaling**: $a=s_x, d=s_y, c=0, b=0$. Point scales relative to origin $(0,0)$.
*   **Rotation**: $a=\cos\theta, d=\cos\theta, c=-\sin\theta, b=\sin\theta$. Rotates around origin $(0,0)$ by angle $\theta$ (in radians).

### Concatenation and Order of Operations
If $M_{\text{CTM}}$ is the current coordinate matrix, applying a new transformation matrix $T$ updates the CTM via right-multiplication:

$$M_{\text{CTM}}' = M_{\text{CTM}} \times T$$

Because matrix multiplication is **non-commutative**:

$$M_1 \times M_2 \ne M_2 \times M_1$$

The order in which you apply transformations changes the result.
*   **Translate then Rotate**: The grid is shifted first, and then rotated around the *new* origin.
*   **Rotate then Translate**: The grid is rotated around the original origin first. The subsequent shift occurs along the rotated axes, moving the grid diagonally relative to the viewer.

---

## 3. Code Demonstration

The following Swift code draws a recursive spiral pattern by repeatedly rotating and translating the CTM inside a loop.

```swift
import Core
import Geometry
import Renderers

func drawCTMSpiralDemo() {
    var context = GraphicsContext()
    
    let canvasSize: Double = 400
    context.setFillColor(Color(r: 0.05, g: 0.05, b: 0.1, a: 1.0)) // Night blue
    context.fill(Rect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    
    // Move coordinate origin to the center of the canvas
    context.translate(by: canvasSize / 2.0, canvasSize / 2.0)
    
    // Draw a spiral pattern of squares
    context.setFillColor(Color(r: 0.3, g: 0.6, b: 0.9, a: 0.6))
    context.setStrokeColor(Color(r: 0.6, g: 0.8, b: 1.0, a: 1.0))
    context.setLineWidth(1.5)
    
    let steps = 36
    let rotationAngle = Double.pi / 18.0 // 10 degrees per step
    
    let square = Rect(x: -15, y: -15, width: 30, height: 30)
    
    for i in 0..<steps {
        context.saveGState()
        
        // Scale and shift based on index to spiral outward
        let scaleFactor = 1.0 + Double(i) * 0.05
        context.scale(by: scaleFactor, scaleFactor)
        context.translate(by: Double(i) * 3.0, 0.0)
        
        // Draw the square
        context.fill(square)
        context.stroke(square)
        
        context.restoreGState()
        
        // Accumulate rotation globally between steps
        context.rotate(by: rotationAngle)
    }
    
    // Render output
    let renderer = SVGRenderer(width: canvasSize, height: canvasSize)
    do {
        let svg = try renderer.draw(context)
        print("Spiral CTM SVG:\n\(svg)")
    } catch {
        print("Error: \(error)")
    }
}
```

---

## 4. Exercises

1.  **Algebraic Proof**: Let a point be $P(1, 0)$. Calculate its final coordinates under two scenarios:
    *   **Scenario A**: Translate by $(2, 0)$, then rotate by $\pi/2$ ($90^\circ$).
    *   **Scenario B**: Rotate by $\pi/2$, then translate by $(2, 0)$.
2.  **Orbit Helper**: Write a helper function in Swift that draws a circle orbiting around a central point $(cx, cy)$ at a radius $r$ and angle $\theta$, using only CTM operations and drawing a circle at $(0, 0)$.
