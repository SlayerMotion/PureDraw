# Core Graphics (Quartz 2D) Curriculum

This directory contains the lesson-by-lesson curriculum for learning 2D vector graphics drawing and mathematics, using `PureDraw` as the implementation framework.

Each lesson details the core concept, the mathematical foundations, a practical code demonstration in Swift, and exercises.

For the engineering provenance — every specification, paper, book, and article that participated in the implementation, mapped to the code it informed — see [../SOURCES.md](../SOURCES.md).

---

## Lessons Index

### 1. [Lesson 1: The Native Coordinate Space](lesson1_coordinates.md)
*   **Concepts**: Vector geometry, floating-point coordinates, and coordinate system origins.
*   **The Math**: Cartesian bottom-left origin $(0,0)$ vs. top-left origin.
*   **Code Demo**: Initializing a virtual graphics context and drawing points.

### 2. [Lesson 2: Context State & The GState Stack](lesson2_gstate.md)
*   **Concepts**: Global context drawing states, state encapsulation, and isolation.
*   **The Math**: Last-In-First-Out (LIFO) stack operations.
*   **Code Demo**: Saving and restoring state configurations to prevent parameter bleeding.

### 3. [Lesson 3: Paths, Lines, & Joins](lesson3_paths.md)
*   **Concepts**: Stroke rendering, centerlines, caps, and joins.
*   **The Math**: Centerline offset expansions and miter limit trigonometric calculations.
*   **Code Demo**: Constructing polygon paths with custom line caps and joins.

### 4. [Lesson 4: Bezier Curves & Curve Subdivision](lesson4_curves.md)
*   **Concepts**: Curves, control points, and rasterization.
*   **The Math**: Parametric quadratic and cubic Bezier equations.
*   **Code Demo**: Drawing smooth continuous curves and understanding segment resolution.

### 5. [Lesson 5: The Current Transformation Matrix (CTM)](lesson5_ctm.md)
*   **Concepts**: Grid transformation matrices.
*   **The Math**: 3x3 affine matrices (translation, scale, rotation, skew) and matrix concatenation order.
*   **Code Demo**: Designing recursive rotational patterns using CTM transforms.

### 6. [Lesson 6: Clipping Boundaries](lesson6_clipping.md)
*   **Concepts**: Restricting context drawing areas.
*   **The Math**: Area intersections ($A \cap B$) and fill rules (Non-Zero Winding vs. Even-Odd).
*   **Code Demo**: Masking an image or path crop, and using GState restore to unclip.

### 7. [Lesson 7: Projective Transforms (Homographies)](lesson7_projective.md)
*   **Concepts**: 3D perspective mapping inside 2D coordinates.
*   **The Math**: Projective 3x3 matrices, homogeneous coordinate $w$, and horizon clipping.
*   **Code Demo**: Warping a flat grid image onto an arbitrary 3D perspective quad.

### 8. [Lesson 8: Text & Typography](lesson8_typography.md)
*   **Concepts**: Vector glyph parsing and drawing.
*   **The Math**: Font matrices and advance vectors.
*   **Code Demo**: Parsing Outline glyphs and drawing them as vector paths.

### 9. [Lesson 9: Gradients & Patterns](lesson9_gradients.md)
*   **Concepts**: Complex vector fills.
*   **The Math**: Multi-stop axial/radial color interpolation and tiled coordinate grids.
*   **Code Demo**: Drawing linear/radial gradients and tiling custom patterns.

### 10. [Lesson 10: The Backing Store (The Core Animation Bridge)](lesson10_backing_store.md)
*   **Concepts**: Memory allocations and GPU compositing.
*   **The Math**: Calculating backing store RAM size: $\text{Width} \times \text{Height} \times 4 \text{ bytes} \times \text{Scale}^2$.
*   **Code Demo**: Profiling app memory, finding `drawRect:` bottlenecks, and migrating custom drawing to GPU-backed layers.

### 11. [Lesson 11: Antialiasing & Coverage Rasterization](lesson11_antialiasing.md)
*   **Concepts**: Fractional pixel coverage, aliasing vs. soft edges, hybrid sub-row + analytic rasterization.
*   **The Math**: Scanline span detection, analytic horizontal overlap, $C = \min(1, \sum \frac{1}{N}\,\text{overlap})$, premultiplied compositing.
*   **Code Demo**: Filling a triangle and reading the partial-coverage alpha ramp along a slanted edge.

### 12. [Lesson 12: Continuous Corners — the Squircle](lesson12_squircle.md)
*   **Concepts**: Curvature continuity, the superellipse myth, circular vs. continuous corners.
*   **The Math**: The Bézier circle constant $\kappa = \frac{4}{3}(\sqrt{2}-1)$, fixed-ratio cubic corners, edge consumption $\rho = 1.52866$, the capsule limit.
*   **Code Demo**: Drawing the same rectangle with circular and continuous corners and comparing the outlines.

### 13. [Lesson 13: Encoding Pixels — PNG Chunks, zlib & DEFLATE](lesson13_png_deflate.md)
*   **Concepts**: Chunked containers, scanline filtering, the encode/decode compression asymmetry.
*   **The Math**: The zlib stream framing, stored DEFLATE blocks ($\texttt{LEN}/\sim\!\texttt{LEN}$), Adler-32 and CRC-32 checksums.
*   **Code Demo**: Encoding a rendered image to PNG bytes and verifying the signature and IHDR chunk.
