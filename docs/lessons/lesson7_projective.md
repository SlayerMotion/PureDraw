# Lesson 7: Projective Transforms (Homographies)

Affine transformations preserve parallel lines, but rendering 3D perspective requires projection. Master 3x3 projective matrices and the math of homogeneous coordinate division to map flat textures onto 3D planes.

---

## 1. Core Concepts

### Linear vs. Projective Mapping
*   **Affine Transformations**: Map parallel lines to parallel lines. Grids remain flat and uniformly spaced.
*   **Projective Transformations (Homographies)**: Map parallel lines to converging lines that meet at a vanishing point. This simulates depth, allowing a 2D graphics engine to warp shapes and textures in 3D perspective.

### Homogeneous Coordinates & Division
To map a flat rectangular texture onto an arbitrary four-cornered polygon (quad) in perspective, we use a 3D coordinate system where points are represented by three values $[x, y, w]^T$. The variable $w$ represents the depth or scale factor.

---

## 2. Mathematical Foundations

### The Projective Matrix
A projective transform is represented by a $3 \times 3$ matrix:

$$\begin{bmatrix} x' \\ y' \\ w' \end{bmatrix} = \begin{bmatrix} m_{11} & m_{21} & m_{31} \\ m_{12} & m_{22} & m_{32} \\ m_{13} & m_{23} & m_{33} \end{bmatrix} \begin{bmatrix} x \\ y \\ 1 \end{bmatrix}$$

Multiplying out the rows gives:

$$x' = m_{11} x + m_{21} y + m_{31}$$
$$y' = m_{12} x + m_{22} y + m_{32}$$
$$w' = m_{13} x + m_{23} y + m_{33}$$

To convert these homogeneous coordinates back to physical 2D Cartesian coordinates $(x_{\text{proj}}, y_{\text{proj}})$, we must divide the spatial coordinates by the depth scale $w'$:

$$x_{\text{proj}} = \frac{x'}{w'} = \frac{m_{11} x + m_{21} y + m_{31}}{m_{13} x + m_{23} y + m_{33}}$$
$$y_{\text{proj}} = \frac{y'}{w'} = \frac{m_{12} x + m_{22} y + m_{32}}{m_{13} x + m_{23} y + m_{33}}$$

### Horizon Clipping
The denominator $w'$ represents the distance of the point relative to the camera plane.
*   If $w' > 0$: The point is in front of the camera and is visible.
*   If $w' = 0$: The point lies exactly on the horizon line (representing infinite perspective scaling).
*   If $w' < 0$: The point is behind the camera viewpoint.

When rasterizing, if a polygon segment crosses the camera plane (where $w'$ transitions from positive to negative), the rasterizer must clip the polygon at the plane $w' = \epsilon$. Failing to clip leads to division by zero and inverted mirroring of coordinates.

---

## 3. Code Demonstration

The following Swift example loads a mock image and uses `ProjectiveTransform` to warp that image onto a perspective quad.

```swift
import Core
import Geometry
import Renderers

func drawProjectiveTransformDemo() {
    var context = GraphicsContext()
    let canvasSize: Double = 400
    
    // Fill background with black
    context.setFillColor(Color(r: 0.0, g: 0.0, b: 0.0, a: 1.0))
    context.fill(Rect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    
    // Create a mock image (a grid of 100x100 pixels)
    var pixels = [UInt8](repeating: 0, count: 100 * 100 * 4)
    for y in 0..<100 {
        for x in 0..<100 {
            let idx = (y * 100 + x) * 4
            // Create a red/green checkerboard pattern
            let isBorder = (x % 10 == 0) || (y % 10 == 0)
            if isBorder {
                pixels[idx] = 255     // Red
                pixels[idx + 1] = 255 // Green
                pixels[idx + 2] = 255 // Blue
            } else {
                pixels[idx] = UInt8(x * 2)
                pixels[idx + 1] = UInt8(y * 2)
                pixels[idx + 2] = 50
            }
            pixels[idx + 3] = 255 // Alpha
        }
    }
    let image = Image(width: 100, height: 100, pixels: pixels)
    
    // Define a projective matrix (homography) that warps the rect (0,0,100,100)
    // into a perspective trapezoid peaking toward the top-center.
    // Mat: [m11, m12, m13, m21, m22, m23, m31, m32, m33]
    let transform = ProjectiveTransform(
        m11: 2.5,  m12: 0.0,  m13: 0.0,
        m21: 0.0,  m22: 2.0,  m23: 0.003, // m23 adds perspective foreshortening along Y
        m31: 50.0, m32: 50.0, m33: 1.0
    )
    
    // Render the image warped onto the canvas using the homography transform
    let sourceRect = Rect(x: 0, y: 0, width: 100, height: 100)
    context.draw(image, in: sourceRect, mappingTo: transform)
    
    // Render the output canvas
    let renderer = SVGRenderer(width: canvasSize, height: canvasSize)
    do {
        let svg = try renderer.draw(context)
        print("Projective Warp SVG:\n\(svg)")
    } catch {
        print("Error during projection warp: \(error)")
    }
}
```

---

## 4. Exercises

1.  **Perspective Coordinate Mapping**: Given the projective matrix:
    $$T = \begin{bmatrix} 2 & 0 & 10 \\ 0 & 2 & 20 \\ 0 & 0.01 & 1 \end{bmatrix}$$
    calculate the 2D Cartesian coordinates $(x_{\text{proj}}, y_{\text{proj}})$ for the input point $P(50, 100)$.
2.  **Horizon Intersection**: Find the set of points $(x, y)$ that lie exactly on the projection horizon (where $w' = 0$) for the matrix in Exercise 1.
