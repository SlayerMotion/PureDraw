//
//  Validations+Geometry.swift
//  PureDraw
//

extension Validation {
    
    /// Validates that an affine transform matrix is mathematically invertible (its determinant is non-zero).
    /// Singular matrices cannot be inverted and often cause rendering anomalies or crashes in graphics pipelines.
    public static var matrixIsReversible: Validation<Document, AffineTransform> {
        .init(
            description: "Transform matrix determinant is non-zero (matrix is invertible)",
            check: { context in
                context.subject.determinant != 0
            }
        )
    }
    
    /// Validates that a rectangle has valid dimensions (width and height must be positive).
    /// Negative dimensions are mathematically undefined for physical bounds and lead to undefined clipping.
    public static var rectHasValidDimensions: Validation<Document, Rect> {
        .init(
            description: "Rectangle width and height are positive",
            check: { context in
                context.subject.width >= 0 && context.subject.height >= 0
            }
        )
    }
    
    /// Validates that a point contains finite, valid coordinates (no NaN or infinite values).
    public static var pointIsFinite: Validation<Document, Point> {
        .init(
            description: "Point coordinates are finite (not NaN or Infinity)",
            check: { context in
                context.subject.x.isFinite && context.subject.y.isFinite
            }
        )
    }
}
