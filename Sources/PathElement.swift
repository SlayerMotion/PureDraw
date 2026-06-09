//
//  PathElement.swift
//  PureDraw
//

/// The primitive mathematical operations that construct a 2D vector path.
///
/// This enumeration maps 1:1 with the fundamental path construction operators
/// defined in the PDF specification and Apple's CoreGraphics (\`CGPathElementType\`).
public enum PathElement: Equatable, Sendable, Validatable {
    /// Begins a new subpath at the specified point. (PDF: \`m\`)
    case move(to: Point)

    /// Appends a straight line segment from the current point to the specified point. (PDF: \`l\`)
    case line(to: Point)

    /// Appends a quadratic Bézier curve from the current point to the specified end point,
    /// using a single control point.
    case quadCurve(to: Point, control: Point)

    /// Appends a cubic Bézier curve from the current point to the specified end point,
    /// using two control points. (PDF: \`c\`)
    case cubicCurve(to: Point, control1: Point, control2: Point)

    /// Closes the current subpath by drawing a straight line back to the most recent \`.move(to:)\` point. (PDF: \`h\`)
    case close
}
