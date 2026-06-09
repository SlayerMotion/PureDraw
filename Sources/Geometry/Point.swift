import Validation

//
//  Point.swift
//  PureDraw
//

/// A point in a two-dimensional coordinate system.
public struct Point: Equatable, Sendable, Validatable {
    public var x: Double
    public var y: Double

    public static let zero = Point(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Applies an affine transformation to the point.
    public func applying(_ t: AffineTransform) -> Point {
        let newX = t.a * x + t.c * y + t.tx
        let newY = t.b * x + t.d * y + t.ty
        return Point(x: newX, y: newY)
    }

    /// Applies a projective transformation to the point.
    public func applying(_ t: ProjectiveTransform) -> Point {
        let w = t.m13 * x + t.m23 * y + t.m33
        guard w != 0.0, w.isFinite else {
            return Point(x: .nan, y: .nan)
        }
        let newX = (t.m11 * x + t.m21 * y + t.m31) / w
        let newY = (t.m12 * x + t.m22 * y + t.m32) / w
        return Point(x: newX, y: newY)
    }

    public static var defaultValidator: Validator<Point> {
        Validator().validating(.pointIsFinite)
    }
}
