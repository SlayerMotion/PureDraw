import Geometry
import Validation

//
//  GraphicsContext.swift
//  PureDraw
//

/// A stateful coordinator for constructing 2D drawing paths and recording drawing commands.
///
/// `GraphicsContext` uses value semantics. Copying a context duplicates its current graphics state,
/// allowing for local state modifications that do not affect parent contexts.
public struct GraphicsContext: Sendable, Validatable {
    /// The recorded sequence of drawing commands.
    public private(set) var commands: [DrawOperation] = []

    /// The current path being built.
    public private(set) var currentPath: Path = .init()

    /// The current point of the context's path.
    public var currentPoint: Point {
        currentPath.currentPoint
    }

    /// The current active graphics state.
    public private(set) var currentState: GraphicState = .init()

    /// A stack of saved graphics states.
    private var stateStack: [GraphicState] = []

    private struct LayerState: Equatable {
        let alpha: Double
        let shadow: Shadow?
        let blendMode: BlendMode
    }

    /// A stack of transparency layer states.
    private var layerStateStack: [LayerState] = []

    public init() {}

    // MARK: - State Management

    /// Pushes a copy of the current graphics state onto the graphics state stack.
    public mutating func saveGState() {
        stateStack.append(currentState)
    }

    /// Pops the most recently saved graphics state off the stack, restoring it as the current state.
    public mutating func restoreGState() {
        guard !stateStack.isEmpty else { return }
        currentState = stateStack.removeLast()
    }

    // MARK: - Style Setters

    /// Sets the color used to stroke a path.
    public mutating func setStrokeColor(_ color: Color) {
        currentState.strokeColor = color
    }

    /// Sets the color used to fill a path.
    public mutating func setFillColor(_ color: Color) {
        currentState.fillColor = color
    }

    /// Sets the line width for stroke path operations.
    public mutating func setLineWidth(_ width: Double) {
        currentState.lineWidth = width
    }

    /// Sets the line cap style for stroked lines.
    public mutating func setLineCap(_ cap: LineCap) {
        currentState.lineCap = cap
    }

    /// Sets the line join style for joints of stroked paths.
    public mutating func setLineJoin(_ join: LineJoin) {
        currentState.lineJoin = join
    }

    /// Sets the limit for miter joins.
    public mutating func setMiterLimit(_ limit: Double) {
        currentState.miterLimit = limit
    }

    /// Sets the pattern and phase offset for dashed stroked lines.
    public mutating func setLineDash(phase: Double, lengths: [Double]) {
        currentState.dashPhase = phase
        currentState.dashPattern = lengths
    }

    /// Sets the accuracy of curve rendering.
    public mutating func setFlatness(_ flatness: Double) {
        currentState.flatness = flatness
    }

    /// Sets the overall opacity multiplier.
    public mutating func setAlpha(_ alpha: Double) {
        currentState.alpha = alpha
    }

    /// Sets the blending mode for subsequent drawing operations.
    public mutating func setBlendMode(_ mode: BlendMode) {
        currentState.blendMode = mode
    }

    /// Sets whether anti-aliasing is enabled for subsequent drawing.
    public mutating func setShouldAntialias(_ shouldAntialias: Bool) {
        currentState.shouldAntialias = shouldAntialias
    }

    /// Sets whether anti-aliasing is allowed for this context.
    public mutating func setAllowsAntialiasing(_ allowsAntialiasing: Bool) {
        currentState.allowsAntialiasing = allowsAntialiasing
    }

    /// Sets the image interpolation quality for scaling images.
    public mutating func setInterpolationQuality(_ quality: InterpolationQuality) {
        currentState.interpolationQuality = quality
    }

    /// Sets the rendering intent for subsequent drawing operations.
    public mutating func setRenderingIntent(_ intent: RenderingIntent) {
        currentState.renderingIntent = intent
    }

    /// Sets whether font smoothing is enabled.
    public mutating func setShouldSmoothFonts(_ shouldSmoothFonts: Bool) {
        currentState.shouldSmoothFonts = shouldSmoothFonts
    }

    /// Sets whether font smoothing is allowed.
    public mutating func setAllowsFontSmoothing(_ allowsFontSmoothing: Bool) {
        currentState.allowsFontSmoothing = allowsFontSmoothing
    }

    /// Sets whether to position fonts at subpixel coordinates.
    public mutating func setShouldSubpixelPositionFonts(_ shouldSubpixelPositionFonts: Bool) {
        currentState.shouldSubpixelPositionFonts = shouldSubpixelPositionFonts
    }

    /// Sets whether to quantize fonts at subpixel positions.
    public mutating func setShouldSubpixelQuantizeFonts(_ shouldSubpixelQuantizeFonts: Bool) {
        currentState.shouldSubpixelQuantizeFonts = shouldSubpixelQuantizeFonts
    }

    // MARK: - Coordinate Transformations

    /// Applies a translation to the Current Transformation Matrix (CTM).
    public mutating func translate(by x: Double, _ y: Double) {
        currentState.transform = currentState.transform.translatedBy(x: x, y: y)
    }

    /// Applies a scale transformation to the CTM.
    public mutating func scale(by x: Double, _ y: Double) {
        currentState.transform = currentState.transform.scaledBy(x: x, y: y)
    }

    /// Applies a rotation (in radians) to the CTM.
    public mutating func rotate(by angle: Double) {
        currentState.transform = currentState.transform.rotated(by: angle)
    }

    /// Applies a skew/shear to the CTM.
    public mutating func skew(by x: Double, _ y: Double) {
        currentState.transform = currentState.transform.skewedBy(x: x, y: y)
    }

    /// Concatenates the given transform with the CTM.
    public mutating func concatenate(_ transform: Geometry.AffineTransform) {
        currentState.transform = currentState.transform.concatenating(transform)
    }

    // MARK: - Path Construction

    /// Moves the current path to the specified point, starting a new subpath.
    public mutating func move(to point: Point) {
        currentPath.move(to: point)
    }

    /// Appends a straight line segment to the current path.
    public mutating func addLine(to point: Point) {
        currentPath.addLine(to: point)
    }

    /// Appends a quadratic Bézier curve to the current path.
    public mutating func addQuadCurve(to point: Point, control: Point) {
        currentPath.addQuadCurve(to: point, control: control)
    }

    /// Appends a cubic Bézier curve to the current path.
    public mutating func addCurve(to point: Point, control1: Point, control2: Point) {
        currentPath.addCurve(to: point, control1: control1, control2: control2)
    }

    /// Closes the current subpath of the current path.
    public mutating func closeSubpath() {
        currentPath.closeSubpath()
    }

    /// Adds a rectangle as a complete closed subpath.
    public mutating func addRect(_ rect: Rect) {
        currentPath.addRect(rect)
    }

    /// Adds a sequence of rectangles to the current path.
    public mutating func addRects(_ rects: [Rect]) {
        currentPath.addRects(rects)
    }

    /// Appends the elements of another path to the current path.
    public mutating func addPath(_ path: Path) {
        currentPath.addPath(path)
    }

    /// Adds a sequence of connected line segments between the specified points to the current path.
    public mutating func addLines(between points: [Point]) {
        currentPath.addLines(between: points)
    }

    /// Adds an ellipse that fits inside the specified rectangle.
    public mutating func addEllipse(in rect: Rect) {
        currentPath.addEllipse(in: rect)
    }

    /// Adds a rounded rectangle with the specified corner dimensions.
    public mutating func addRoundedRect(in rect: Rect, cornerWidth: Double, cornerHeight: Double) {
        currentPath.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
    }

    /// Adds a circular arc to the current path.
    public mutating func addArc(
        center: Point,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        clockwise: Bool
    ) {
        currentPath.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )
    }

    /// Adds a relative circular arc to the current path.
    public mutating func addRelativeArc(
        center: Point,
        radius: Double,
        startAngle: Double,
        delta: Double
    ) {
        currentPath.addRelativeArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            delta: delta
        )
    }

    /// Appends a circular arc defined by a tangent and radius to the current path.
    public mutating func addArc(tangent1End: Point, tangent2End: Point, radius: Double) {
        currentPath.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius)
    }

    // MARK: - Drawing Actions

    /// Sets the shadow properties for subsequent drawing operations.
    public mutating func setShadow(offset: Point, blur: Double, color: Color) {
        currentState.shadow = Shadow(offset: offset, blur: blur, color: color)
    }

    /// Clears the shadow from the current graphics state.
    public mutating func clearShadow() {
        currentState.shadow = nil
    }

    /// Records a linear gradient drawing operation.
    /// The gradient fills the current clipping path of the context.
    public mutating func drawLinearGradient(
        _ gradient: Gradient,
        start: Point,
        end: Point,
        options: GradientDrawingOptions = []
    ) {
        commands.append(
            DrawOperation(
                kind: .drawLinearGradient(gradient, start: start, end: end, options: options),
                state: currentState
            )
        )
    }

    /// Records a radial gradient drawing operation.
    /// The gradient fills the current clipping path of the context.
    public mutating func drawRadialGradient(
        _ gradient: Gradient,
        startCenter: Point,
        startRadius: Double,
        endCenter: Point,
        endRadius: Double,
        options: GradientDrawingOptions = []
    ) {
        commands.append(
            DrawOperation(
                kind: .drawRadialGradient(
                    gradient,
                    startCenter: startCenter,
                    startRadius: startRadius,
                    endCenter: endCenter,
                    endRadius: endRadius,
                    options: options
                ),
                state: currentState
            )
        )
    }

    /// Records a stroke command in the buffer using the current state and clears the current path.
    public mutating func strokePath() {
        guard !currentPath.isEmpty else { return }
        commands.append(DrawOperation(kind: .stroke(currentPath), state: currentState))
        currentPath = Path()
    }

    /// Draws a sequence of unconnected line segments.
    ///
    /// For every pair of points (2i, 2i+1), a line segment is drawn.
    public mutating func strokeLineSegments(between points: [Point]) {
        guard points.count >= 2 else { return }
        var segmentsPath = Path()
        for i in stride(from: 0, to: points.count - 1, by: 2) {
            segmentsPath.move(to: points[i])
            segmentsPath.addLine(to: points[i + 1])
        }
        commands.append(DrawOperation(kind: .stroke(segmentsPath), state: currentState))
    }

    /// Records a fill command in the buffer using the current state and clears the current path.
    public mutating func fillPath(using rule: FillRule = .winding) {
        guard !currentPath.isEmpty else { return }
        recordFill(of: currentPath, rule: rule)
        currentPath = Path()
    }

    /// Sets the tiling pattern used by fill operations; pass nil to fill with
    /// the fill color again.
    public mutating func setFillPattern(_ pattern: Pattern?) {
        currentState.fillPattern = pattern
    }

    /// Strokes the specified path using the current graphics state, leaving the current path of the context unchanged.
    public mutating func stroke(_ path: Path) {
        commands.append(DrawOperation(kind: .stroke(path), state: currentState))
    }

    /// Fills the specified path using the current graphics state, leaving the current path of the context unchanged.
    public mutating func fill(_ path: Path, using rule: FillRule = .winding) {
        recordFill(of: path, rule: rule)
    }

    /// Records a fill, expanding into tiled cell operations when a fill
    /// pattern is set so every backend renders patterns with no special
    /// support.
    private mutating func recordFill(of path: Path, rule: FillRule) {
        if let pattern = currentState.fillPattern {
            commands.append(contentsOf: patternFillCommands(of: path, pattern: pattern))
        } else {
            commands.append(DrawOperation(kind: .fill(path, rule: rule), state: currentState))
        }
    }

    /// Strokes the boundary of the specified rectangle using the current graphics state.
    public mutating func stroke(_ rect: Rect) {
        let path = Path(rect: rect)
        stroke(path)
    }

    /// Strokes the boundary of the specified rectangle with the specified line width.
    ///
    /// This method temporarily sets the line width in the graphics state to the specified value.
    public mutating func stroke(_ rect: Rect, width: Double) {
        var tempState = currentState
        tempState.lineWidth = width
        let path = Path(rect: rect)
        commands.append(DrawOperation(kind: .stroke(path), state: tempState))
    }

    /// Fills the interior of the specified rectangle using the current graphics state.
    public mutating func fill(_ rect: Rect) {
        let path = Path(rect: rect)
        fill(path)
    }

    /// Strokes the boundary of an ellipse that fits inside the specified rectangle.
    public mutating func strokeEllipse(in rect: Rect) {
        let path = Path(ellipseIn: rect)
        stroke(path)
    }

    /// Fills the interior of an ellipse that fits inside the specified rectangle.
    public mutating func fillEllipse(in rect: Rect) {
        let path = Path(ellipseIn: rect)
        fill(path)
    }

    /// Intersects the current clipping path with the current path and clears the current path.
    public mutating func clip(using _: FillRule = .winding) {
        guard !currentPath.isEmpty else { return }
        if let existingClip = currentState.clipPath {
            var combined = existingClip
            combined.addPath(currentPath)
            currentState.clipPath = combined
        } else {
            currentState.clipPath = currentPath
        }
        currentPath = Path()
    }

    /// Intersects the current clipping path with the clipping mask defined by the specified image.
    // MARK: - Text State

    /// The text matrix applied to shown glyphs, the `CGContext` text matrix
    /// equivalent. Unlike the graphics state, it is not saved or restored by
    /// `saveGState()` / `restoreGState()`.
    public var textMatrix: Geometry.AffineTransform = .identity

    /// The user-space point where the next glyph is shown.
    public private(set) var textPosition: Point = .zero

    public mutating func setFont(_ font: Font) {
        currentState.font = font
    }

    public mutating func setFontSize(_ size: Double) {
        currentState.fontSize = size
    }

    public mutating func setCharacterSpacing(_ spacing: Double) {
        currentState.characterSpacing = spacing
    }

    public mutating func setTextDrawingMode(_ mode: TextDrawingMode) {
        currentState.textDrawingMode = mode
    }

    public mutating func setTextPosition(_ position: Point) {
        textPosition = position
    }

    // MARK: - Text Showing

    /// Shows text starting at the given position, advancing the text position.
    public mutating func showText(_ text: String, at position: Point) {
        setTextPosition(position)
        showText(text)
    }

    /// Shows text at the current text position, advancing it. Unmapped
    /// characters render as the font's missing glyph. The source string is
    /// retained so SVG and PDF can emit native selectable text.
    public mutating func showText(_ text: String) {
        guard let font = currentState.font else { return }
        let glyphs = text.unicodeScalars.map { font.glyphIndex(for: $0) ?? 0 }
        recordText(glyphs: glyphs, text: text)
    }

    /// Shows glyphs starting at the given position, advancing the text position.
    public mutating func showGlyphs(_ glyphs: [Int], at position: Point) {
        setTextPosition(position)
        showGlyphs(glyphs)
    }

    /// Shows glyphs by index at the current text position. The text position
    /// advances by each glyph's advance width plus character spacing, along
    /// the text matrix's x axis. Glyph-index runs carry no source string, so
    /// they render as outlines on every backend.
    public mutating func showGlyphs(_ glyphs: [Int]) {
        recordText(glyphs: glyphs, text: nil)
    }

    /// Records a text run as a single high-level operation and advances the
    /// pen. Backends without native text expand it to glyph outlines via
    /// `textLoweredCommands`; SVG and PDF can render it as real text.
    private mutating func recordText(glyphs: [Int], text: String?) {
        guard let font = currentState.font, font.unitsPerEm > 0 else { return }

        commands.append(DrawOperation(
            kind: .showText(
                glyphs: glyphs,
                text: text,
                font: font,
                fontSize: currentState.fontSize,
                drawingMode: currentState.textDrawingMode,
                textMatrix: textMatrix,
                position: textPosition
            ),
            state: currentState
        ))

        // Advance the pen so the next show starts after this run.
        let scale = currentState.fontSize / Double(font.unitsPerEm)
        for glyph in glyphs {
            let advance = font.advanceWidth(forGlyph: glyph) * scale + currentState.characterSpacing
            textPosition = Point(
                x: textPosition.x + advance * textMatrix.a,
                y: textPosition.y + advance * textMatrix.b
            )
        }
    }

    /// Stamps a recorded layer into the given rect, scaling its contents.
    public mutating func draw(_ layer: Layer, in rect: Rect) {
        commands.append(DrawOperation(kind: .drawLayer(layer, rect: rect), state: currentState))
    }

    /// Stamps a recorded layer at the given point at its natural size.
    public mutating func draw(_ layer: Layer, at point: Point) {
        draw(layer, in: Rect(x: point.x, y: point.y, width: layer.width, height: layer.height))
    }

    public mutating func clip(to rect: Rect, mask: Image) {
        currentState.maskImage = mask
        currentState.maskRect = rect
        currentState.maskTransform = currentState.transform
    }

    /// Returns a boolean value indicating whether the context's current path contains the specified point.
    ///
    /// - Parameters:
    ///   - point: The point to check.
    ///   - rule: The fill rule to use (winding or evenOdd).
    /// - Returns: `true` if the path contains the point; otherwise, `false`.
    public func pathContains(_ point: Point, using rule: FillRule = .winding) -> Bool {
        currentPath.contains(point, using: rule)
    }

    /// Begins a transparency layer. Subsequent drawing is accumulated and composite rendered as a single layer.
    public mutating func beginTransparencyLayer() {
        let layerState = LayerState(alpha: currentState.alpha, shadow: currentState.shadow, blendMode: currentState.blendMode)
        layerStateStack.append(layerState)
        commands.append(DrawOperation(kind: .beginTransparencyLayer, state: currentState))

        // Temporarily reset style attributes that accumulate on the layer container
        currentState.alpha = 1.0
        currentState.shadow = nil
        currentState.blendMode = .normal
    }

    /// Ends the most recently begun transparency layer, compositing it using the restored styles.
    public mutating func endTransparencyLayer() {
        guard !layerStateStack.isEmpty else { return }
        let originalState = layerStateStack.removeLast()

        currentState.alpha = originalState.alpha
        currentState.shadow = originalState.shadow
        currentState.blendMode = originalState.blendMode
        commands.append(DrawOperation(kind: .endTransparencyLayer, state: currentState))
    }

    /// Draws the specified image scaled within the target rect frame.
    public mutating func draw(_ image: Image, in rect: Rect) {
        commands.append(DrawOperation(kind: .drawImage(image, rect: rect), state: currentState))
    }

    public static var defaultValidator: Validator<GraphicsContext> {
        Validator().validating(.transparencyLayersAreBalanced)
    }
}
