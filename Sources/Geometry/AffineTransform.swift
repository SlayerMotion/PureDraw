import Foundation
import Validation

//
//  AffineTransform.swift
//  PureDraw
//

/// An affine transformation matrix for use in drawing 2D graphics.
///
/// This struct mirrors the mathematical behavior of `CGAffineTransform`.
/// It represents a 3x3 matrix, but since the third column is always `[0, 0, 1]`,
/// only the first six values (`a, b, c, d, tx, ty`) are stored and operated on.
///
/// ```
/// [ a   b   0 ]
/// [ c   d   0 ]
/// [ tx  ty  1 ]
/// ```
public struct AffineTransform: Equatable, Sendable, Validatable {
    /// The `a` entry: x scale (and x contribution to x).
    public var a: Double
    /// The `b` entry: the y shear (x contribution to y).
    public var b: Double
    /// The `c` entry: the x shear (y contribution to x).
    public var c: Double
    /// The `d` entry: y scale (y contribution to y).
    public var d: Double
    /// The x translation.
    public var tx: Double
    /// The y translation.
    public var ty: Double

    /// The identity transform: `[1 0 0 1 0 0]`.
    public static let identity = AffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    /// Creates a transform from its six matrix entries.
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    /// Creates a transform that translates by `(tx, ty)`.
    public static func translation(x: Double, y: Double) -> AffineTransform {
        AffineTransform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    /// Creates a transform that scales by `(sx, sy)`.
    public static func scale(x: Double, y: Double) -> AffineTransform {
        AffineTransform(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    /// Creates a transform that rotates by `angle` radians.
    public static func rotation(angle: Double) -> AffineTransform {
        let sine = sin(angle)
        let cosine = cos(angle)
        return AffineTransform(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    /// Creates a transform that skews/shears by `(x, y)` factors.
    public static func skew(x: Double, y: Double) -> AffineTransform {
        AffineTransform(a: 1, b: y, c: x, d: 1, tx: 0, ty: 0)
    }

    /// Concatenates `t2` onto `self`. Mathematically, this is `self * t2`.
    public func concatenating(_ t2: AffineTransform) -> AffineTransform {
        let newA = a * t2.a + b * t2.c
        let newB = a * t2.b + b * t2.d
        let newC = c * t2.a + d * t2.c
        let newD = c * t2.b + d * t2.d
        let newTx = tx * t2.a + ty * t2.c + t2.tx
        let newTy = tx * t2.b + ty * t2.d + t2.ty

        return AffineTransform(a: newA, b: newB, c: newC, d: newD, tx: newTx, ty: newTy)
    }

    /// Translates the transform by `(x, y)`.
    public func translatedBy(x: Double, y: Double) -> AffineTransform {
        concatenating(.translation(x: x, y: y))
    }

    /// Scales the transform by `(x, y)`.
    public func scaledBy(x: Double, y: Double) -> AffineTransform {
        concatenating(.scale(x: x, y: y))
    }

    /// Rotates the transform by `angle` radians.
    public func rotated(by angle: Double) -> AffineTransform {
        concatenating(.rotation(angle: angle))
    }

    /// Skews the transform by `(x, y)` factors.
    public func skewedBy(x: Double, y: Double) -> AffineTransform {
        concatenating(.skew(x: x, y: y))
    }
}

public extension AffineTransform {
    /// The determinant of the transformation matrix.
    ///
    /// If the determinant is 0, the matrix is singular and cannot be inverted.
    var determinant: Double {
        (a * d) - (b * c)
    }

    /// Returns the inverse of the affine transform.
    ///
    /// If the transform is singular (determinant is 0), it cannot be inverted.
    /// In this case, the function returns `self` unchanged to prevent a crash,
    /// which mirrors the defensive behavior of `CGAffineTransformInvert`.
    func inverted() -> AffineTransform {
        let det = determinant
        if det == 0 {
            return self // Singular matrix fallback
        }

        return AffineTransform(
            a: d / det,
            b: -b / det,
            c: -c / det,
            d: a / det,
            tx: (c * ty - d * tx) / det,
            ty: (b * tx - a * ty) / det
        )
    }

    static var defaultValidator: Validator<AffineTransform> {
        Validator()
            .validating(.matrixIsReversible)
            .validating(.matrixIsFinite)
    }
}

public extension AffineTransform {
    /// The motions an affine transform is built from: a translation, a rotation, a scale on each axis,
    /// and a shear. `rotation` and `skew` are in radians, matching the rest of this type.
    struct Decomposed: Equatable, Sendable {
        public var translationX, translationY: Double
        public var rotation: Double
        public var scaleX, scaleY: Double
        public var skew: Double

        public init(translationX: Double, translationY: Double, rotation: Double, scaleX: Double, scaleY: Double, skew: Double) {
            self.translationX = translationX
            self.translationY = translationY
            self.rotation = rotation
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.skew = skew
        }
    }

    /// Factor the transform into rotation, scale, and shear by Gram-Schmidt (QR factorization) of the
    /// 2x2 linear part, reading translation straight off `tx, ty`.
    ///
    /// The rows of the linear part are `row0 = (a, b)` and `row1 = (c, d)`; a point p maps to p · M.
    /// We recover M = R(theta) · S(sx, sy) · K(k), a rotation, an axis scale, then a unit shear
    /// K = | 1 0 ; k 1 |:
    ///
    ///   1. `sx = |row0| = hypot(a, b)`. The unit row `u = row0 / sx = (a1, b1)` is the image of the
    ///      x-axis, so `theta = atan2(b1, a1)`.
    ///   2. The shear is row1's component along u: `shear = u . row1 = a1*c + b1*d`.
    ///   3. Orthogonalize: `row1' = row1 - shear*u`; then `sy = |row1'|` and the shear factor is
    ///      `k = shear / sy`, giving `skew = atan(k)`.
    ///   4. A reflection (`determinant < 0`) is not a rotation+scale, so fold it into `sx`: negate sx,
    ///      u, and shear. This keeps theta clean and puts the flip on one axis.
    ///
    /// The inverse is `recomposed(_:)`, and `recomposed(decomposed())` reproduces the matrix to within
    /// floating-point dust (asserted by the round-trip test).
    func decomposed() -> Decomposed {
        let determinant = (a * d) - (b * c)
        var scaleX = ((a * a) + (b * b)).squareRoot()
        var unitA = scaleX != 0 ? a / scaleX : 0
        var unitB = scaleX != 0 ? b / scaleX : 0
        var shear = (unitA * c) + (unitB * d)
        let orthoC = c - (unitA * shear)
        let orthoD = d - (unitB * shear)
        let scaleY = ((orthoC * orthoC) + (orthoD * orthoD)).squareRoot()
        if scaleY != 0 { shear /= scaleY }
        if determinant < 0 {
            scaleX = -scaleX
            unitA = -unitA
            unitB = -unitB
            shear = -shear
        }
        return Decomposed(
            translationX: tx, translationY: ty,
            rotation: atan2(unitB, unitA),
            scaleX: scaleX, scaleY: scaleY,
            skew: atan(shear)
        )
    }

    /// Rebuild a transform from its decomposition. With `c0 = cos(rotation)`, `s0 = sin(rotation)`, and
    /// `t = tan(skew)`: `a = sx*c0`, `b = sx*s0`, `c = sy*(c0*t - s0)`, `d = sy*(s0*t + c0)`.
    static func recomposed(_ parts: Decomposed) -> AffineTransform {
        let c0 = cos(parts.rotation)
        let s0 = sin(parts.rotation)
        let t = tan(parts.skew)
        return AffineTransform(
            a: parts.scaleX * c0,
            b: parts.scaleX * s0,
            c: parts.scaleY * ((c0 * t) - s0),
            d: parts.scaleY * ((s0 * t) + c0),
            tx: parts.translationX,
            ty: parts.translationY
        )
    }
}
