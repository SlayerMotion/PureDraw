import Foundation

/// A resolution-independent mathematical description of shapes and lines.
///
/// A \`Path\` is essentially a command buffer of \`PathElement\` primitives. It does not contain 
/// any rendering state (like color or line width); it purely defines geometry.
public struct Path: Equatable, Sendable, Validatable {
    
    /// The ordered sequence of elements that make up the path.
    public private(set) var elements: [PathElement]
    
    /// Initializes an empty path.
    public init() {
        self.elements = []
    }
    
    /// Initializes a path with a predefined array of elements.
    public init(elements: [PathElement]) {
        self.elements = elements
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
        return elements.isEmpty
    }
    
    /// Applies an affine transformation to all elements in the path, returning a new transformed path.
    public func applying(_ transform: AffineTransform) -> Path {
        let transformedElements: [PathElement] = elements.map { element in
            switch element {
            case .move(let to):
                return .move(to: to.applying(transform))
            case .line(let to):
                return .line(to: to.applying(transform))
            case .quadCurve(let to, let control):
                return .quadCurve(to: to.applying(transform), control: control.applying(transform))
            case .cubicCurve(let to, let control1, let control2):
                return .cubicCurve(
                    to: to.applying(transform),
                    control1: control1.applying(transform),
                    control2: control2.applying(transform)
                )
            case .close:
                return .close
            }
        }
        return Path(elements: transformedElements)
    }
    
    /// Applies a projective transformation to all elements in the path, returning a new transformed path.
    public func applying(_ transform: ProjectiveTransform) -> Path {
        let transformedElements: [PathElement] = elements.map { element in
            switch element {
            case .move(let to):
                return .move(to: to.applying(transform))
            case .line(let to):
                return .line(to: to.applying(transform))
            case .quadCurve(let to, let control):
                return .quadCurve(to: to.applying(transform), control: control.applying(transform))
            case .cubicCurve(let to, let control1, let control2):
                return .cubicCurve(
                    to: to.applying(transform),
                    control1: control1.applying(transform),
                    control2: control2.applying(transform)
                )
            case .close:
                return .close
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
        
        guard rx > 0 && ry > 0 else {
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
                case .move(let to), .line(let to), .quadCurve(let to, _), .cubicCurve(let to, _, _):
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
        
        for i in 0..<segmentCount {
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
            case .move(let to), .line(let to), .quadCurve(let to, _), .cubicCurve(let to, _, _):
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
}
