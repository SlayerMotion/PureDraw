import Foundation

/// A projective transformation (homography) matrix for use in drawing 2D graphics with perspective distortion.
///
/// This struct represents a 3x3 matrix, allowing for non-affine transformations such as perspective warps.
/// Points are treated as row vectors `[x y 1]` and transformed as:
///
/// ```
/// [x_new, y_new, w_new] = [x, y, 1] * [ m11 m12 m13 ]
///                                     [ m21 m22 m23 ]
///                                     [ m31 m32 m33 ]
/// ```
///
/// The final 2D coordinates are obtained by dividing by the homogeneous coordinate `w_new`:
/// `x_final = x_new / w_new`
/// `y_final = y_new / w_new`
public struct ProjectiveTransform: Equatable, Sendable, Validatable {
    public var m11: Double
    public var m12: Double
    public var m13: Double
    public var m21: Double
    public var m22: Double
    public var m23: Double
    public var m31: Double
    public var m32: Double
    public var m33: Double

    /// The identity projective transform.
    public static let identity = ProjectiveTransform(
        m11: 1.0, m12: 0.0, m13: 0.0,
        m21: 0.0, m22: 1.0, m23: 0.0,
        m31: 0.0, m32: 0.0, m33: 1.0,
    )

    public init(
        m11: Double, m12: Double, m13: Double,
        m21: Double, m22: Double, m23: Double,
        m31: Double, m32: Double, m33: Double,
    ) {
        self.m11 = m11
        self.m12 = m12
        self.m13 = m13
        self.m21 = m21
        self.m22 = m22
        self.m23 = m23
        self.m31 = m31
        self.m32 = m32
        self.m33 = m33
    }

    /// Initializes a projective transform from a standard affine transform.
    public init(_ affine: AffineTransform) {
        m11 = affine.a
        m12 = affine.b
        m13 = 0.0
        m21 = affine.c
        m22 = affine.d
        m23 = 0.0
        m31 = affine.tx
        m32 = affine.ty
        m33 = 1.0
    }

    /// Creates a projective transform mapping the unit square `[0,1] x [0,1]` to the specified four points.
    ///
    /// The source points mapped are:
    /// - `(0, 0)` -> `p0`
    /// - `(1, 0)` -> `p1`
    /// - `(1, 1)` -> `p2`
    /// - `(0, 1)` -> `p3`
    public static func unitSquareToQuad(p0: Point, p1: Point, p2: Point, p3: Point) -> ProjectiveTransform {
        let dx1 = p1.x - p2.x
        let dx2 = p3.x - p2.x
        let sx = p0.x - p1.x - p3.x + p2.x

        let dy1 = p1.y - p2.y
        let dy2 = p3.y - p2.y
        let sy = p0.y - p1.y - p3.y + p2.y

        let det = dx1 * dy2 - dx2 * dy1

        let g: Double
        let h: Double
        if abs(det) < 1e-9 {
            g = 0.0
            h = 0.0
        } else {
            g = (sx * dy2 - sy * dx2) / det
            h = (dx1 * sy - dy1 * sx) / det
        }

        let e = p0.x
        let f = p0.y

        let a = p1.x - p0.x + g * p1.x
        let b = p1.y - p0.y + g * p1.y
        let c = p3.x - p0.x + h * p3.x
        let d = p3.y - p0.y + h * p3.y

        return ProjectiveTransform(
            m11: a, m12: b, m13: g,
            m21: c, m22: d, m23: h,
            m31: e, m32: f, m33: 1.0,
        )
    }

    /// Creates a projective transform mapping a given source rectangle to the specified four points.
    ///
    /// The source rectangle corners are mapped as follows:
    /// - top-left `(rect.minX, rect.minY)` -> `p0`
    /// - top-right `(rect.maxX, rect.minY)` -> `p1`
    /// - bottom-right `(rect.maxX, rect.maxY)` -> `p2`
    /// - bottom-left `(rect.minX, rect.maxY)` -> `p3`
    public static func rectToQuad(_ rect: Rect, p0: Point, p1: Point, p2: Point, p3: Point) -> ProjectiveTransform {
        let scaleX = rect.width == 0.0 ? 1.0 : 1.0 / rect.width
        let scaleY = rect.height == 0.0 ? 1.0 : 1.0 / rect.height

        // Transform mapping rect to unit square [0,1]x[0,1]
        let toUnit = AffineTransform(
            a: scaleX, b: 0.0,
            c: 0.0, d: scaleY,
            tx: -rect.origin.x * scaleX,
            ty: -rect.origin.y * scaleY,
        )

        let unitToQuad = unitSquareToQuad(p0: p0, p1: p1, p2: p2, p3: p3)
        return ProjectiveTransform(toUnit).concatenated(with: unitToQuad)
    }

    /// Concatenates `t2` onto `self`. Mathematically, this is `self * t2`.
    public func concatenated(with t2: ProjectiveTransform) -> ProjectiveTransform {
        ProjectiveTransform(
            m11: m11 * t2.m11 + m12 * t2.m21 + m13 * t2.m31,
            m12: m11 * t2.m12 + m12 * t2.m22 + m13 * t2.m32,
            m13: m11 * t2.m13 + m12 * t2.m23 + m13 * t2.m33,

            m21: m21 * t2.m11 + m22 * t2.m21 + m23 * t2.m31,
            m22: m21 * t2.m12 + m22 * t2.m22 + m23 * t2.m32,
            m23: m21 * t2.m13 + m22 * t2.m23 + m23 * t2.m33,

            m31: m31 * t2.m11 + m32 * t2.m21 + m33 * t2.m31,
            m32: m31 * t2.m12 + m32 * t2.m22 + m33 * t2.m32,
            m33: m31 * t2.m13 + m32 * t2.m23 + m33 * t2.m33,
        )
    }

    /// The determinant of the 3x3 transformation matrix.
    public var determinant: Double {
        let c11 = m22 * m33 - m23 * m32
        let c12 = m21 * m33 - m23 * m31
        let c13 = m21 * m32 - m22 * m31
        return m11 * c11 - m12 * c12 + m13 * c13
    }

    /// Returns the inverse of the projective transform.
    ///
    /// If the transform is singular (determinant is 0), returns `self` unchanged to prevent a crash.
    public func inverted() -> ProjectiveTransform {
        let det = determinant
        if det == 0.0 {
            return self
        }

        let c11 = m22 * m33 - m23 * m32
        let c12 = -(m21 * m33 - m23 * m31)
        let c13 = m21 * m32 - m22 * m31

        let c21 = -(m12 * m33 - m13 * m32)
        let c22 = m11 * m33 - m13 * m31
        let c23 = -(m11 * m32 - m12 * m31)

        let c31 = m12 * m23 - m13 * m22
        let c32 = -(m11 * m23 - m13 * m21)
        let c33 = m11 * m22 - m12 * m21

        return ProjectiveTransform(
            m11: c11 / det, m12: c21 / det, m13: c31 / det,
            m21: c12 / det, m22: c22 / det, m23: c32 / det,
            m31: c13 / det, m32: c23 / det, m33: c33 / det,
        )
    }

    public static var defaultValidator: Validator<ProjectiveTransform> {
        Validator()
            .validating(.projectiveMatrixIsReversible)
            .validating(.projectiveMatrixIsFinite)
    }
}
