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
    public private(set) var currentPath: Path = Path()
    
    /// The current active graphics state.
    public private(set) var currentState: GraphicState = GraphicState()
    
    /// A stack of saved graphics states.
    private var stateStack: [GraphicState] = []
    
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
    
    /// Sets the overall opacity multiplier.
    public mutating func setAlpha(_ alpha: Double) {
        currentState.alpha = alpha
    }
    
    /// Sets the blending mode for subsequent drawing operations.
    public mutating func setBlendMode(_ mode: BlendMode) {
        currentState.blendMode = mode
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
    
    /// Concatenates the given transform with the CTM.
    public mutating func concatenate(_ transform: AffineTransform) {
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
        move(to: rect.origin)
        addLine(to: Point(x: rect.origin.x + rect.width, y: rect.origin.y))
        addLine(to: Point(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height))
        addLine(to: Point(x: rect.origin.x, y: rect.origin.y + rect.height))
        closeSubpath()
    }
    
    /// Appends the elements of another path to the current path.
    public mutating func addPath(_ path: Path) {
        currentPath.addPath(path)
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
    
    // MARK: - Drawing Actions
    
    /// Records a stroke command in the buffer using the current state and clears the current path.
    public mutating func strokePath() {
        guard !currentPath.isEmpty else { return }
        commands.append(DrawOperation(kind: .stroke(currentPath), state: currentState))
        currentPath = Path()
    }
    
    /// Records a fill command in the buffer using the current state and clears the current path.
    public mutating func fillPath(using rule: FillRule = .winding) {
        guard !currentPath.isEmpty else { return }
        commands.append(DrawOperation(kind: .fill(currentPath, rule: rule), state: currentState))
        currentPath = Path()
    }
    
    /// Intersects the current clipping path with the current path and clears the current path.
    public mutating func clip(using rule: FillRule = .winding) {
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
}
