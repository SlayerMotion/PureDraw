# Lesson 8: Text & Typography

Text is not drawn as a simple raster print. Inside a vector engine, fonts are collections of mathematical outlines scaled and positioned dynamically. Master font matrices, em spaces, and pen advances to render typography.

---

## 1. Core Concepts

### Characters vs. Glyphs
*   **Character**: A semantic unit of written language, represented by a Unicode scalar value (e.g., `U+0041` for 'A').
*   **Glyph**: A specific visual representation of a character outline (or collection of characters).

A single character can map to different glyphs depending on the font style (e.g., standard vs. italic) or ligatures (e.g., the characters "f" and "i" merging into a single "ﬁ" glyph). The translation between characters and glyphs is resolved by the font's **character-to-glyph map** (cmap).

### The Em Square
Font designers build vector glyph outlines inside a virtual square called the **em square**. The size of this square (measured in font units) is defined by the **unitsPerEm** parameter (typically 1000 for PostScript fonts and 2048 for TrueType fonts). All coordinate boundaries (ascender, descender, glyph paths) are relative to this virtual square.

---

## 2. Mathematical Foundations

### Font Outlines Scaling
To render a glyph at a user space point size $S$ from a font outline defined in units per em $U$, the engine scales the outline coordinates by the scale factor:

$$\text{Scale} = \frac{S}{U}$$

If a glyph outline contains a node at point $(x_{\text{glyph}}, y_{\text{glyph}})$ in font units, its coordinate in user space points is:

$$x_{\text{user}} = x_{\text{glyph}} \times \frac{S}{U}$$
$$y_{\text{user}} = y_{\text{glyph}} \times \frac{S}{U}$$

### Pen Advance Mathematics
After drawing a glyph at position $\mathbf{P}_i = (x_i, y_i)$, the coordinate of the pen for the subsequent glyph $\mathbf{P}_{i+1}$ must advance along the text layout direction. If the glyph has an advance width $A$ (in font units), the character spacing is $c$ (in user points), and the text matrix is $T$, the pen advance is calculated as:

$$\Delta x = \left(A \times \frac{S}{U} + c\right) \times T_a$$
$$\Delta y = \left(A \times \frac{S}{U} + c\right) \times T_b$$

where $T_a$ and $T_b$ are the transformation coefficients of the text matrix.

$$\mathbf{P}_{i+1} = \left(x_i + \Delta x, y_i + \Delta y\right)$$

---

## 3. Code Demonstration

The following Swift example loads a system font outline, sets the font size and character spacing, and draws a string onto the context, detailing how the text matrix rotates the text.

```swift
import Core
import Geometry
import Renderers

func drawTypographyDemo() {
    var context = GraphicsContext()
    let width: Double = 400
    let height: Double = 200
    
    // Fill canvas background
    context.setFillColor(Color(r: 0.1, g: 0.1, b: 0.15, a: 1.0))
    context.fill(Rect(x: 0, y: 0, width: width, height: height))
    
    // Load a font (We mock a basic font skeleton or load via CFFFont)
    // For demonstration, we assume standard font initialization
    // font unitsPerEm = 1000
    let font = Font.defaultFont()
    context.setFont(font)
    
    // Set typography parameters
    context.setFontSize(24.0)
    context.setCharacterSpacing(2.0)
    context.setFillColor(Color(r: 0.9, g: 0.9, b: 0.9, a: 1.0))
    
    // Rotate the text matrix by 15 degrees (0.26 radians)
    // This rotates the text layout direction relative to the baseline
    context.textMatrix = AffineTransform.identity.rotated(by: 0.26)
    
    // Show text at coordinate (50, 50)
    context.showText("Quartz Vector Text", at: Point(x: 50, y: 50))
    
    // Render
    let renderer = SVGRenderer(width: width, height: height)
    do {
        let svg = try renderer.draw(context)
        print("Text SVG Output:\n\(svg)")
    } catch {
        print("Typography rendering failed: \(error)")
    }
}
```

---

## 4. Exercises

1.  **Glyph Dimension Scaling**: A font has `unitsPerEm = 2048`. The letter "M" glyph outline has a height of $1434$ units. Calculate the height of the drawn glyph on screen in points when the font size is set to $32.0$ points.
2.  **Pen Position Tracking**: Using a font size of $20$ points, `unitsPerEm = 1000`, and character spacing of $1.5$ points:
    *   Find the new pen position after rendering a glyph with an advance width of $650$ units, starting at $(100, 100)$ with a text matrix equal to `AffineTransform.identity`.
