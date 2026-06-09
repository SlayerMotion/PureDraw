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
        self.elements = []
        addRect(rect)
    }

    /// Creates a path containing a single ellipse.
    public init(ellipseIn rect: Rect) {
        self.elements = []
        addEllipse(in: rect)
    }

    /// Creates a path containing a single rounded rectangle.
    public init(roundedRect rect: Rect, cornerWidth: Double, cornerHeight: Double) {
        self.elements = []
        addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
    }

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

    /// Adds a rounded rectangle with the specified corner dimensions.
    public mutating func addRoundedRect(in rect: Rect, cornerWidth: Double, cornerHeight: Double) {
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

        move(to: Point(x: rect.minX + rx, y: rect.minY))

        addLine(to: Point(x: rect.maxX - rx, y: rect.minY))

        addCurve(
            to: Point(x: rect.maxX, y: rect.minY + ry),
            control1: Point(x: rect.maxX - rx + rx * kappa, y: rect.minY),
            control2: Point(x: rect.maxX, y: rect.minY + ry - ry * kappa)
        )

        addLine(to: Point(x: rect.maxX, y: rect.maxY - ry))

        addCurve(
            to: Point(x: rect.maxX - rx, y: rect.maxY),
            control1: Point(x: rect.maxX, y: rect.maxY - ry + ry * kappa),
            control2: Point(x: rect.maxX - rx + rx * kappa, y: rect.maxY)
        )

        addLine(to: Point(x: rect.minX + rx, y: rect.maxY))

        addCurve(
            to: Point(x: rect.minX, y: rect.maxY - ry),
            control1: Point(x: rect.minX + rx - rx * kappa, y: rect.maxY),
            control2: Point(x: rect.minX, y: rect.maxY - ry + ry * kappa)
        )

        addLine(to: Point(x: rect.minX, y: rect.minY + ry))

        addCurve(
            to: Point(x: rect.minX + rx, y: rect.minY),
            control1: Point(x: rect.minX, y: rect.minY + ry - ry * kappa),
            control2: Point(x: rect.minX + rx - rx * kappa, y: rect.minY)
        )

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
}
