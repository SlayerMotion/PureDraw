//
//  Path.swift
//  PureDraw
//

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
}
