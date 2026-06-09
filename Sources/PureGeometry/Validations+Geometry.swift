import PureValidation

//
//  Validations+Geometry.swift
//  PureDraw
//

public extension Validation {
    /// Validates that an affine transform matrix is mathematically invertible (its determinant is non-zero).
    /// Singular matrices cannot be inverted and often cause rendering anomalies or crashes in graphics pipelines.
    static var matrixIsReversible: Validation<Document, AffineTransform> {
        .init(
            description: "Transform matrix determinant is non-zero (matrix is invertible)",
            check: { context in
                context.subject.determinant != 0
            },
        )
    }

    /// Validates that all elements of the affine transform are finite.
    static var matrixIsFinite: Validation<Document, AffineTransform> {
        .init(
            description: "Transform matrix components are finite",
            check: { context in
                let t = context.subject
                return t.a.isFinite && t.b.isFinite && t.c.isFinite && t.d.isFinite && t.tx.isFinite && t.ty.isFinite
            },
        )
    }

    /// Validates that a projective transform matrix is mathematically invertible (its determinant is non-zero).
    static var projectiveMatrixIsReversible: Validation<Document, ProjectiveTransform> {
        .init(
            description: "Projective transform matrix determinant is non-zero (matrix is invertible)",
            check: { context in
                context.subject.determinant != 0
            },
        )
    }

    /// Validates that all elements of the projective transform are finite.
    static var projectiveMatrixIsFinite: Validation<Document, ProjectiveTransform> {
        .init(
            description: "Projective transform matrix components are finite",
            check: { context in
                let t = context.subject
                return t.m11.isFinite && t.m12.isFinite && t.m13.isFinite &&
                    t.m21.isFinite && t.m22.isFinite && t.m23.isFinite &&
                    t.m31.isFinite && t.m32.isFinite && t.m33.isFinite
            },
        )
    }

    /// Validates that a rectangle has valid dimensions (width and height must be positive).
    /// Negative dimensions are mathematically undefined for physical bounds and lead to undefined clipping.
    static var rectHasValidDimensions: Validation<Document, Rect> {
        .init(
            description: "Rectangle width and height are positive",
            check: { context in
                context.subject.width >= 0 && context.subject.height >= 0
            },
        )
    }

    /// Validates that a rectangle's dimensions are finite.
    static var rectIsFinite: Validation<Document, Rect> {
        .init(
            description: "Rectangle dimensions are finite",
            check: { context in
                context.subject.width.isFinite && context.subject.height.isFinite
            },
        )
    }

    /// Validates that a point contains finite, valid coordinates (no NaN or infinite values).
    static var pointIsFinite: Validation<Document, Point> {
        .init(
            description: "Point coordinates are finite (not NaN or Infinity)",
            check: { context in
                context.subject.x.isFinite && context.subject.y.isFinite
            },
        )
    }
}
