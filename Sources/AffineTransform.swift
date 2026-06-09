import Foundation
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
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    /// The identity transform: `[1 0 0 1 0 0]`.
    public static let identity = AffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

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

    /// Concatenates `t2` onto `self`. Mathematically, this is `self * t2`.
    public func concatenating(_ t2: AffineTransform) -> AffineTransform {
        let newA = self.a * t2.a + self.b * t2.c
        let newB = self.a * t2.b + self.b * t2.d
        let newC = self.c * t2.a + self.d * t2.c
        let newD = self.c * t2.b + self.d * t2.d
        let newTx = self.tx * t2.a + self.ty * t2.c + t2.tx
        let newTy = self.tx * t2.b + self.ty * t2.d + t2.ty

        return AffineTransform(a: newA, b: newB, c: newC, d: newD, tx: newTx, ty: newTy)
    }
    
    /// Translates the transform by `(x, y)`.
    public func translatedBy(x: Double, y: Double) -> AffineTransform {
        self.concatenating(.translation(x: x, y: y))
    }
    
    /// Scales the transform by `(x, y)`.
    public func scaledBy(x: Double, y: Double) -> AffineTransform {
        self.concatenating(.scale(x: x, y: y))
    }
    
    /// Rotates the transform by `angle` radians.
    public func rotated(by angle: Double) -> AffineTransform {
        self.concatenating(.rotation(angle: angle))
    }
}

public extension AffineTransform {
    /// The determinant of the transformation matrix.
    ///
    /// If the determinant is 0, the matrix is singular and cannot be inverted.
    var determinant: Double {
        return (a * d) - (b * c)
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
}
