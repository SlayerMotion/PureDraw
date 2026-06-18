import Foundation
import Geometry
import Validation

/// A resolution-independent mathematical description of shapes and lines.
///
/// A \`Path\` is essentially a command buffer of \`PathElement\` primitives. It does not contain
/// any rendering state (like color or line width); it purely defines geometry.
public struct Path: Equatable, Sendable, Validatable {
    /// The ordered sequence of elements that make up the path.
    public private(set) var elements: [PathElement]

    /// Initializes an empty path.
    public init() {
        elements = []
    }

    /// Initializes a path with a predefined array of elements.
    public init(elements: [PathElement]) {
        self.elements = elements
    }

    /// Creates a path containing a single rectangle.
    public init(rect: Rect) {
        elements = []
        addRect(rect)
    }

    /// Creates a path containing a single ellipse.
    public init(ellipseIn rect: Rect) {
        elements = []
        addEllipse(in: rect)
    }

    /// Creates a path containing a single rounded rectangle.
    public init(roundedRect rect: Rect, cornerWidth: Double, cornerHeight: Double) {
        elements = []
        addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
    }

    /// Validates that the element sequence is well formed (each subpath opens with a move).
    public static var defaultValidator: Validator<Path> {
        Validator().validating(.pathStructureIsValid)
    }

    /// Appends a move command to start a new subpath.
    public mutating func move(to point: Point) {
        elements.append(.move(to: point))
    }

    /// Appends a line command.
    public mutating func addLine(to point: Point) {
        elements.append(.line(to: point))
    }

    /// Appends a quadratic Bézier curve.
    public mutating func addQuadCurve(to point: Point, control: Point) {
        elements.append(.quadCurve(to: point, control: control))
    }

    /// Appends a cubic Bézier curve.
    public mutating func addCurve(to point: Point, control1: Point, control2: Point) {
        elements.append(.cubicCurve(to: point, control1: control1, control2: control2))
    }

    /// Closes the current subpath.
    public mutating func closeSubpath() {
        elements.append(.close)
    }

    /// Returns true if the path contains no elements.
    public var isEmpty: Bool {
        elements.isEmpty
    }

    /// Returns the current point of the path, or Point.zero if empty.
    public var currentPoint: Point {
        var current = Point.zero
        var subpathStart = Point.zero

        for element in elements {
            switch element {
            case let .move(to):
                current = to
                subpathStart = to
            case let .line(to):
                current = to
            case let .quadCurve(to, _):
                current = to
            case let .cubicCurve(to, _, _):
                current = to
            case .close:
                current = subpathStart
            }
        }
        return current
    }

    /// Applies an affine transformation to all elements in the path, returning a new transformed path.
    public func applying(_ transform: Geometry.AffineTransform) -> Path {
        let transformedElements: [PathElement] = elements.map { element in
            switch element {
            case let .move(to):
                .move(to: to.applying(transform))
            case let .line(to):
                .line(to: to.applying(transform))
            case let .quadCurve(to, control):
                .quadCurve(to: to.applying(transform), control: control.applying(transform))
            case let .cubicCurve(to, control1, control2):
                .cubicCurve(
                    to: to.applying(transform),
                    control1: control1.applying(transform),
                    control2: control2.applying(transform)
                )
            case .close:
                .close
            }
        }
        return Path(elements: transformedElements)
    }

    /// Applies a projective transformation to all elements in the path, returning a new transformed path.
    public func applying(_ transform: ProjectiveTransform) -> Path {
        let transformedElements: [PathElement] = elements.map { element in
            switch element {
            case let .move(to):
                .move(to: to.applying(transform))
            case let .line(to):
                .line(to: to.applying(transform))
            case let .quadCurve(to, control):
                .quadCurve(to: to.applying(transform), control: control.applying(transform))
            case let .cubicCurve(to, control1, control2):
                .cubicCurve(
                    to: to.applying(transform),
                    control1: control1.applying(transform),
                    control2: control2.applying(transform)
                )
            case .close:
                .close
            }
        }
        return Path(elements: transformedElements)
    }

    /// Appends the elements of another path to this path.
    public mutating func addPath(_ path: Path) {
        elements.append(contentsOf: path.elements)
    }

    /// Adds an ellipse that fits inside the specified rectangle.
    public mutating func addEllipse(in rect: Rect) {
        let cx = rect.origin.x + rect.width / 2.0
        let cy = rect.origin.y + rect.height / 2.0
        let rx = rect.width / 2.0
        let ry = rect.height / 2.0

        let kappa = 0.5522847498307933

        move(to: Point(x: cx + rx, y: cy))

        addCurve(
            to: Point(x: cx, y: cy + ry),
            control1: Point(x: cx + rx, y: cy + ry * kappa),
            control2: Point(x: cx + rx * kappa, y: cy + ry)
        )

        addCurve(
            to: Point(x: cx - rx, y: cy),
            control1: Point(x: cx - rx * kappa, y: cy + ry),
            control2: Point(x: cx - rx, y: cy + ry * kappa)
        )

        addCurve(
            to: Point(x: cx, y: cy - ry),
            control1: Point(x: cx - rx, y: cy - ry * kappa),
            control2: Point(x: cx - rx * kappa, y: cy - ry)
        )

        addCurve(
            to: Point(x: cx + rx, y: cy),
            control1: Point(x: cx + rx * kappa, y: cy - ry),
            control2: Point(x: cx + rx, y: cy - ry * kappa)
        )

        closeSubpath()
    }

    /// Adds a rectangle with Apple's *continuous* (squircle) corners: the exact
    /// shape `UIBezierPath(roundedRect:cornerRadius:)` and SwiftUI's
    /// `RoundedCornerStyle.continuous` produce. The curvature ramps smoothly from
    /// the straight edge into the corner instead of jumping at a circular arc, so
    /// there is no visible junction.
    ///
    /// Each corner is three cubic Bézier segments whose control points are the
    /// fixed dimensionless ratios of the corner radius reverse-engineered from
    /// `UIBezierPath`; the corner consumes `1.528665` times the radius along each
    /// edge. This is a fixed shape, not a tunable smoothing: Apple's real corner is
    /// a fixed-ratio Bézier, not a superellipse (a superellipse fits it worse than a
    /// plain circle).
    ///
    /// Source for the exact constants: Liam Rosenfeld, "My Quest for the Apple Icon
    /// Shape" (https://liamrosenfeld.com/posts/apple_icon_quest/), an inverse-mapping
    /// extraction of the `UIBezierPath` control points.
    ///
    /// Large-radius behavior: Apple's exact near-capsule corner is proprietary and
    /// not publicly specified (see Figma, "Desperately seeking squircles",
    /// https://www.figma.com/blog/desperately-seeking-squircles/, on how corner
    /// smoothing degrades at capsules). When `1.528665 * radius` would exceed half
    /// the shorter side, the corner is scaled so adjacent corners exactly meet,
    /// preserving the continuous-curvature shape (a smooth capsule) rather than
    /// reverting to a circular arc.
    public mutating func addContinuousRoundedRect(in rect: Rect, cornerRadius: Double, corners: RectCorner = .all) {
        let minSide = min(rect.width, rect.height)
        guard minSide > 0 else { return }
        // Consumption along each edge is edgeRatio * radius, clamped to half the
        // shorter side so adjacent corners never overlap; the corner then scales to
        // that consumption. edgeRatio is also the corner's terminal (u, v) ratio
        // below, so the same constant drives both: the edges meet the curve exactly
        // and the closing segment collapses to zero.
        let edgeRatio = 1.52866498
        let consumption = min(edgeRatio * abs(cornerRadius), minSide / 2.0)
        guard consumption > 0 else {
            move(to: rect.origin)
            addLine(to: Point(x: rect.maxX, y: rect.minY))
            addLine(to: Point(x: rect.maxX, y: rect.maxY))
            addLine(to: Point(x: rect.minX, y: rect.maxY))
            closeSubpath()
            return
        }
        let p = consumption
        let r = consumption / edgeRatio // effective corner scale

        /// One corner: `inAxis` points from the corner vertex toward where the curve
        /// starts (along the incoming edge), `outAxis` toward where it ends (along
        /// the outgoing edge). The (u, v) literals are Rosenfeld's extracted ratios.
        func corner(_ vertex: Point, inAxis: Point, outAxis: Point) {
            func at(_ u: Double, _ v: Double) -> Point {
                Point(x: vertex.x + (u * inAxis.x + v * outAxis.x) * r, y: vertex.y + (u * inAxis.y + v * outAxis.y) * r)
            }
            addCurve(to: at(0.63149379, 0.07491139), control1: at(1.08849296, 0), control2: at(0.86840694, 0))
            addCurve(to: at(0.07491139, 0.63149379), control1: at(0.37282383, 0.16905956), control2: at(0.16905956, 0.37282383))
            addCurve(to: at(0, edgeRatio), control1: at(0, 0.86840694), control2: at(0, 1.08849296))
        }

        // Per-corner consumption: a rounded corner eats `p` of each adjoining edge; a
        // square corner eats 0, so the edge runs straight to the vertex and no curve is
        // drawn there. The edge endpoints below use these offsets so the same code path
        // serves a fully rounded rect (`corners == .all`) and any subset.
        let pTL = corners.contains(.minXMinY) ? p : 0
        let pTR = corners.contains(.maxXMinY) ? p : 0
        let pBL = corners.contains(.minXMaxY) ? p : 0
        let pBR = corners.contains(.maxXMaxY) ? p : 0

        move(to: Point(x: rect.minX + pTL, y: rect.minY))
        addLine(to: Point(x: rect.maxX - pTR, y: rect.minY))
        if corners.contains(.maxXMinY) {
            corner(Point(x: rect.maxX, y: rect.minY), inAxis: Point(x: -1, y: 0), outAxis: Point(x: 0, y: 1))
        }
        addLine(to: Point(x: rect.maxX, y: rect.maxY - pBR))
        if corners.contains(.maxXMaxY) {
            corner(Point(x: rect.maxX, y: rect.maxY), inAxis: Point(x: 0, y: -1), outAxis: Point(x: -1, y: 0))
        }
        addLine(to: Point(x: rect.minX + pBL, y: rect.maxY))
        if corners.contains(.minXMaxY) {
            corner(Point(x: rect.minX, y: rect.maxY), inAxis: Point(x: 1, y: 0), outAxis: Point(x: 0, y: -1))
        }
        addLine(to: Point(x: rect.minX, y: rect.minY + pTL))
        if corners.contains(.minXMinY) {
            corner(Point(x: rect.minX, y: rect.minY), inAxis: Point(x: 0, y: 1), outAxis: Point(x: 1, y: 0))
        }
        closeSubpath()
    }

    /// Adds a rounded rectangle with circular corners of the specified
    /// dimensions. For Apple-style continuous corners, use
    /// `addContinuousRoundedRect(in:cornerRadius:)`.
    public mutating func addRoundedRect(in rect: Rect, cornerWidth: Double, cornerHeight: Double, corners: RectCorner = .all) {
        let rx = min(abs(cornerWidth), rect.width / 2.0)
        let ry = min(abs(cornerHeight), rect.height / 2.0)

        guard rx > 0, ry > 0 else {
            move(to: rect.origin)
            addLine(to: Point(x: rect.origin.x + rect.width, y: rect.origin.y))
            addLine(to: Point(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height))
            addLine(to: Point(x: rect.origin.x, y: rect.origin.y + rect.height))
            closeSubpath()
            return
        }

        let kappa = 0.5522847498307933

        // Per-corner radius offsets: a rounded corner pulls each adjoining edge in by
        // (rx, ry); a square corner uses 0 so the edge meets the vertex and the corner's
        // arc is skipped. The same code serves a full rounded rect and any subset.
        // Each edge in the walk is pulled in by the radius only at a rounded corner; a
        // square corner uses 0, so the edge meets the vertex and the arc is skipped.
        let rxTL = corners.contains(.minXMinY) ? rx : 0
        let ryTL = corners.contains(.minXMinY) ? ry : 0
        let rxTR = corners.contains(.maxXMinY) ? rx : 0
        let ryBR = corners.contains(.maxXMaxY) ? ry : 0
        let rxBL = corners.contains(.minXMaxY) ? rx : 0

        move(to: Point(x: rect.minX + rxTL, y: rect.minY))

        addLine(to: Point(x: rect.maxX - rxTR, y: rect.minY))
        if corners.contains(.maxXMinY) {
            addCurve(
                to: Point(x: rect.maxX, y: rect.minY + ry),
                control1: Point(x: rect.maxX - rx + rx * kappa, y: rect.minY),
                control2: Point(x: rect.maxX, y: rect.minY + ry - ry * kappa)
            )
        }

        addLine(to: Point(x: rect.maxX, y: rect.maxY - ryBR))
        if corners.contains(.maxXMaxY) {
            addCurve(
                to: Point(x: rect.maxX - rx, y: rect.maxY),
                control1: Point(x: rect.maxX, y: rect.maxY - ry + ry * kappa),
                control2: Point(x: rect.maxX - rx + rx * kappa, y: rect.maxY)
            )
        }

        addLine(to: Point(x: rect.minX + rxBL, y: rect.maxY))
        if corners.contains(.minXMaxY) {
            addCurve(
                to: Point(x: rect.minX, y: rect.maxY - ry),
                control1: Point(x: rect.minX + rx - rx * kappa, y: rect.maxY),
                control2: Point(x: rect.minX, y: rect.maxY - ry + ry * kappa)
            )
        }

        addLine(to: Point(x: rect.minX, y: rect.minY + ryTL))
        if corners.contains(.minXMinY) {
            addCurve(
                to: Point(x: rect.minX + rx, y: rect.minY),
                control1: Point(x: rect.minX, y: rect.minY + ry - ry * kappa),
                control2: Point(x: rect.minX + rx - rx * kappa, y: rect.minY)
            )
        }

        closeSubpath()
    }

    /// Adds a circular arc to the path.
    public mutating func addArc(
        center: Point,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        clockwise: Bool
    ) {
        var sweep = endAngle - startAngle
        let twoPi = 2.0 * .pi

        if clockwise {
            if sweep < 0 {
                sweep = sweep.truncatingRemainder(dividingBy: twoPi) + twoPi
            }
        } else {
            if sweep > 0 {
                sweep = sweep.truncatingRemainder(dividingBy: -twoPi) - twoPi
            }
        }

        let maxSegmentAngle = .pi / 2.0
        let segmentCount = max(1, Int(ceil((abs(sweep) - 1e-9) / maxSegmentAngle)))
        let deltaTheta = sweep / Double(segmentCount)

        let startPt = Point(
            x: center.x + radius * cos(startAngle),
            y: center.y + radius * sin(startAngle)
        )

        if !isEmpty {
            var lastPoint: Point? = nil
            if let lastElement = elements.last {
                switch lastElement {
                case let .move(to), let .line(to), let .quadCurve(to, _), let .cubicCurve(to, _, _):
                    lastPoint = to
                case .close:
                    break
                }
            }
            if let last = lastPoint {
                let dx = last.x - startPt.x
                let dy = last.y - startPt.y
                if sqrt(dx * dx + dy * dy) > 1e-9 {
                    addLine(to: startPt)
                }
            } else {
                addLine(to: startPt)
            }
        } else {
            move(to: startPt)
        }

        let kappa = 4.0 / 3.0 * tan(deltaTheta / 4.0)

        for i in 0 ..< segmentCount {
            let theta0 = startAngle + Double(i) * deltaTheta
            let theta1 = theta0 + deltaTheta

            let p0 = Point(x: center.x + radius * cos(theta0), y: center.y + radius * sin(theta0))
            let p3 = Point(x: center.x + radius * cos(theta1), y: center.y + radius * sin(theta1))

            let t0 = Point(x: -sin(theta0), y: cos(theta0))
            let t1 = Point(x: -sin(theta1), y: cos(theta1))

            let p1 = Point(x: p0.x + kappa * radius * t0.x, y: p0.y + kappa * radius * t0.y)
            let p2 = Point(x: p3.x - kappa * radius * t1.x, y: p3.y - kappa * radius * t1.y)

            addCurve(to: p3, control1: p1, control2: p2)
        }
    }

    /// Adds a relative circular arc to the path.
    public mutating func addRelativeArc(
        center: Point,
        radius: Double,
        startAngle: Double,
        delta: Double
    ) {
        addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: startAngle + delta,
            clockwise: delta >= 0
        )
    }

    /// Appends a circular arc defined by a tangent and radius to the current path.
    public mutating func addArc(tangent1End: Point, tangent2End: Point, radius: Double) {
        guard radius >= 0 else { return }

        var currentPoint = Point.zero
        var hasCurrentPoint = false

        for element in elements {
            switch element {
            case let .move(to), let .line(to), let .quadCurve(to, _), let .cubicCurve(to, _, _):
                currentPoint = to
                hasCurrentPoint = true
            case .close:
                break
            }
        }

        if !hasCurrentPoint {
            move(to: tangent1End)
            return
        }

        let p0 = currentPoint
        let t1 = tangent1End
        let t2 = tangent2End

        let dx1 = p0.x - t1.x
        let dy1 = p0.y - t1.y
        let dx2 = t2.x - t1.x
        let dy2 = t2.y - t1.y

        let len1 = sqrt(dx1 * dx1 + dy1 * dy1)
        let len2 = sqrt(dx2 * dx2 + dy2 * dy2)

        if len1 < 1e-9 || len2 < 1e-9 {
            addLine(to: t1)
            return
        }

        let v1x = dx1 / len1
        let v1y = dy1 / len1
        let v2x = dx2 / len2
        let v2y = dy2 / len2

        let dot = v1x * v2x + v1y * v2y
        let cross = v1x * v2y - v1y * v2x

        if abs(cross) < 1e-9 {
            addLine(to: t1)
            return
        }

        let theta = acos(max(-1.0, min(1.0, dot)))
        let halfTheta = theta / 2.0
        let d = radius / tan(halfTheta)

        let q1 = Point(x: t1.x + d * v1x, y: t1.y + d * v1y)
        let q2 = Point(x: t1.x + d * v2x, y: t1.y + d * v2y)

        let h = radius / sin(halfTheta)

        let bx = v1x + v2x
        let by = v1y + v2y
        let blen = sqrt(bx * bx + by * by)

        guard blen > 1e-9 else {
            addLine(to: t1)
            return
        }

        let ux = bx / blen
        let uy = by / blen

        let c = Point(x: t1.x + h * ux, y: t1.y + h * uy)

        let a1 = atan2(q1.y - c.y, q1.x - c.x)
        let a2 = atan2(q2.y - c.y, q2.x - c.x)

        addLine(to: q1)

        let clockwise = cross < 0
        addArc(center: c, radius: radius, startAngle: a1, endAngle: a2, clockwise: clockwise)
    }

    /// Adds a sequence of connected line segments between the specified points.
    public mutating func addLines(between points: [Point]) {
        guard !points.isEmpty else { return }
        move(to: points[0])
        for i in 1 ..< points.count {
            addLine(to: points[i])
        }
    }

    /// Adds a rectangle as a complete closed subpath.
    public mutating func addRect(_ rect: Rect) {
        move(to: rect.origin)
        addLine(to: Point(x: rect.origin.x + rect.width, y: rect.origin.y))
        addLine(to: Point(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height))
        addLine(to: Point(x: rect.origin.x, y: rect.origin.y + rect.height))
        closeSubpath()
    }

    /// Adds a sequence of rectangles to the path.
    public mutating func addRects(_ rects: [Rect]) {
        for rect in rects {
            addRect(rect)
        }
    }

    /// Transforms all points in the path using a custom deformation/displacement function.
    public func deforming(_ transform: (Point) -> Point) -> Path {
        let deformedElements: [PathElement] = elements.map { element in
            switch element {
            case let .move(to):
                .move(to: transform(to))
            case let .line(to):
                .line(to: transform(to))
            case let .quadCurve(to, control):
                .quadCurve(to: transform(to), control: transform(control))
            case let .cubicCurve(to, control1, control2):
                .cubicCurve(
                    to: transform(to),
                    control1: transform(control1),
                    control2: transform(control2)
                )
            case .close:
                .close
            }
        }
        return Path(elements: deformedElements)
    }

    /// Returns a new path where long lines and curves are subdivided into smaller segments.
    ///
    /// This is useful before applying non-linear deformations (like crumpling or warping)
    /// to ensure straight lines and curves can bend smoothly.
    public func subdivided(maxSegmentLength: Double) -> Path {
        var subdividedPath = Path()
        var currentPoint = Point.zero
        var subpathStart = Point.zero

        for element in elements {
            switch element {
            case let .move(to):
                subdividedPath.move(to: to)
                currentPoint = to
                subpathStart = to

            case let .line(to):
                let dx = to.x - currentPoint.x
                let dy = to.y - currentPoint.y
                let distance = sqrt(dx * dx + dy * dy)

                if distance > maxSegmentLength, maxSegmentLength > 0 {
                    let steps = Int(ceil(distance / maxSegmentLength))
                    for i in 1 ... steps {
                        let t = Double(i) / Double(steps)
                        let pt = Point(x: currentPoint.x + t * dx, y: currentPoint.y + t * dy)
                        subdividedPath.addLine(to: pt)
                    }
                } else {
                    subdividedPath.addLine(to: to)
                }
                currentPoint = to

            case let .quadCurve(to, control):
                // Approximate curve length by chord length + control point distance
                let dx1 = control.x - currentPoint.x
                let dy1 = control.y - currentPoint.y
                let dx2 = to.x - control.x
                let dy2 = to.y - control.y
                let approxLength = sqrt(dx1 * dx1 + dy1 * dy1) + sqrt(dx2 * dx2 + dy2 * dy2)

                if approxLength > maxSegmentLength, maxSegmentLength > 0 {
                    let steps = Int(ceil(approxLength / maxSegmentLength))
                    for i in 1 ... steps {
                        let t = Double(i) / Double(steps)
                        let mt = 1.0 - t
                        // B(t) = (1-t)^2 * P0 + 2*(1-t)*t * P1 + t^2 * P2
                        let x = mt * mt * currentPoint.x + 2.0 * mt * t * control.x + t * t * to.x
                        let y = mt * mt * currentPoint.y + 2.0 * mt * t * control.y + t * t * to.y
                        subdividedPath.addLine(to: Point(x: x, y: y))
                    }
                } else {
                    subdividedPath.addQuadCurve(to: to, control: control)
                }
                currentPoint = to

            case let .cubicCurve(to, control1, control2):
                let dx1 = control1.x - currentPoint.x
                let dy1 = control1.y - currentPoint.y
                let dx2 = control2.x - control1.x
                let dy2 = control2.y - control1.y
                let dx3 = to.x - control2.x
                let dy3 = to.y - control2.y
                let approxLength = sqrt(dx1 * dx1 + dy1 * dy1) + sqrt(dx2 * dx2 + dy2 * dy2) + sqrt(dx3 * dx3 + dy3 * dy3)

                if approxLength > maxSegmentLength, maxSegmentLength > 0 {
                    let steps = Int(ceil(approxLength / maxSegmentLength))
                    for i in 1 ... steps {
                        let t = Double(i) / Double(steps)
                        let mt = 1.0 - t
                        // B(t) = (1-t)^3 * P0 + 3*(1-t)^2*t * P1 + 3*(1-t)*t^2 * P2 + t^3 * P3
                        let x = mt * mt * mt * currentPoint.x + 3.0 * mt * mt * t * control1.x + 3.0 * mt * t * t * control2.x + t * t * t * to.x
                        let y = mt * mt * mt * currentPoint.y + 3.0 * mt * mt * t * control1.y + 3.0 * mt * t * t * control2.y + t * t * t * to.y
                        subdividedPath.addLine(to: Point(x: x, y: y))
                    }
                } else {
                    subdividedPath.addCurve(to: to, control1: control1, control2: control2)
                }
                currentPoint = to

            case .close:
                subdividedPath.closeSubpath()
                currentPoint = subpathStart
            }
        }
        return subdividedPath
    }

    /// Returns a boolean value indicating whether the path contains the specified point.
    ///
    /// - Parameters:
    ///   - point: The point to check.
    ///   - rule: The fill rule to use (winding or evenOdd).
    /// - Returns: `true` if the path contains the point; otherwise, `false`.
    public func contains(_ point: Point, using rule: FillRule = .winding) -> Bool {
        guard !isEmpty else { return false }

        let polygons = toPolygons()

        switch rule {
        case .winding:
            var wn = 0
            for poly in polygons {
                guard poly.count >= 2 else { continue }
                let count = poly.count
                for i in 0 ..< count {
                    let p1 = poly[i]
                    let p2 = poly[(i + 1) % count]

                    if p1.y <= point.y {
                        if p2.y > point.y {
                            if isLeft(p1, p2, point) > 0 {
                                wn += 1
                            }
                        }
                    } else {
                        if p2.y <= point.y {
                            if isLeft(p1, p2, point) < 0 {
                                wn -= 1
                            }
                        }
                    }
                }
            }
            return wn != 0

        case .evenOdd:
            var inside = false
            for poly in polygons {
                guard poly.count >= 2 else { continue }
                let count = poly.count
                for i in 0 ..< count {
                    let p1 = poly[i]
                    let p2 = poly[(i + 1) % count]

                    if (p1.y > point.y) != (p2.y > point.y) {
                        let intersectX = (p2.x - p1.x) * (point.y - p1.y) / (p2.y - p1.y) + p1.x
                        if point.x < intersectX {
                            inside.toggle()
                        }
                    }
                }
            }
            return inside
        }
    }

    private func isLeft(_ p0: Point, _ p1: Point, _ p2: Point) -> Double {
        (p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)
    }

    /// Flattens the path into one closed polygon per subpath (every subpath is treated as closed),
    /// the form area fills and point-in-polygon tests expect. Use `toPolylines()` for stroking.
    public func toPolygons() -> [[Point]] {
        toPolylines().map { polyline in
            var points = polyline.points
            if let first = points.first, points.last != first {
                points.append(first)
            }
            return points
        }
    }

    /// Flattens the path into one polyline per subpath, preserving whether the
    /// subpath was explicitly closed. Open subpaths are not closed implicitly,
    /// which is the contract stroking requires; use `toPolygons()` for filling.
    public func toPolylines() -> [(points: [Point], isClosed: Bool)] {
        var polylines: [(points: [Point], isClosed: Bool)] = []
        var currentPolygon: [Point] = []
        var currentPoint = Point.zero
        var subpathStart = Point.zero

        for element in elements {
            switch element {
            case let .move(to):
                if !currentPolygon.isEmpty {
                    polylines.append((points: currentPolygon, isClosed: false))
                }
                currentPolygon = [to]
                currentPoint = to
                subpathStart = to

            case let .line(to):
                if currentPolygon.isEmpty {
                    currentPolygon.append(currentPoint)
                }
                currentPolygon.append(to)
                currentPoint = to

            case let .quadCurve(to, control):
                if currentPolygon.isEmpty {
                    currentPolygon.append(currentPoint)
                }
                let dx1 = control.x - currentPoint.x
                let dy1 = control.y - currentPoint.y
                let dx2 = to.x - control.x
                let dy2 = to.y - control.y
                let approxLength = sqrt(dx1 * dx1 + dy1 * dy1) + sqrt(dx2 * dx2 + dy2 * dy2)
                // A non-finite curve length (NaN/Inf control points) traps Int(ceil(...));
                // fall back to a single step, degrading the degenerate curve to its endpoint.
                let steps = approxLength.isFinite ? max(4, Int(ceil(approxLength / 2.0))) : 1
                for i in 1 ... steps {
                    let t = Double(i) / Double(steps)
                    let mt = 1.0 - t
                    let x = mt * mt * currentPoint.x + 2.0 * mt * t * control.x + t * t * to.x
                    let y = mt * mt * currentPoint.y + 2.0 * mt * t * control.y + t * t * to.y
                    currentPolygon.append(Point(x: x, y: y))
                }
                currentPoint = to

            case let .cubicCurve(to, control1, control2):
                if currentPolygon.isEmpty {
                    currentPolygon.append(currentPoint)
                }
                let dx1 = control1.x - currentPoint.x
                let dy1 = control1.y - currentPoint.y
                let dx2 = control2.x - control1.x
                let dy2 = control2.y - control1.y
                let dx3 = to.x - control2.x
                let dy3 = to.y - control2.y
                let approxLength = sqrt(dx1 * dx1 + dy1 * dy1) + sqrt(dx2 * dx2 + dy2 * dy2) + sqrt(dx3 * dx3 + dy3 * dy3)
                // A non-finite curve length (NaN/Inf control points) traps Int(ceil(...));
                // fall back to a single step, degrading the degenerate curve to its endpoint.
                let steps = approxLength.isFinite ? max(4, Int(ceil(approxLength / 2.0))) : 1
                for i in 1 ... steps {
                    let t = Double(i) / Double(steps)
                    let mt = 1.0 - t
                    let x = mt * mt * mt * currentPoint.x + 3.0 * mt * mt * t * control1.x + 3.0 * mt * t * t * control2.x + t * t * t * to.x
                    let y = mt * mt * mt * currentPoint.y + 3.0 * mt * mt * t * control1.y + 3.0 * mt * t * t * control2.y + t * t * t * to.y
                    currentPolygon.append(Point(x: x, y: y))
                }
                currentPoint = to

            case .close:
                if !currentPolygon.isEmpty {
                    polylines.append((points: currentPolygon, isClosed: true))
                    currentPolygon = []
                }
                currentPoint = subpathStart
            }
        }

        if !currentPolygon.isEmpty {
            polylines.append((points: currentPolygon, isClosed: false))
        }

        return polylines
    }
}
