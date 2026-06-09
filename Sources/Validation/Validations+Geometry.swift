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
    
    /// Validates that all elements of the affine transform are finite.
    public static var matrixIsFinite: Validation<Document, AffineTransform> {
        .init(
            description: "Transform matrix components are finite",
            check: { context in
                let t = context.subject
                return t.a.isFinite && t.b.isFinite && t.c.isFinite && t.d.isFinite && t.tx.isFinite && t.ty.isFinite
            }
        )
    }
    
    /// Validates that a projective transform matrix is mathematically invertible (its determinant is non-zero).
    public static var projectiveMatrixIsReversible: Validation<Document, ProjectiveTransform> {
        .init(
            description: "Projective transform matrix determinant is non-zero (matrix is invertible)",
            check: { context in
                context.subject.determinant != 0
            }
        )
    }
    
    /// Validates that all elements of the projective transform are finite.
    public static var projectiveMatrixIsFinite: Validation<Document, ProjectiveTransform> {
        .init(
            description: "Projective transform matrix components are finite",
            check: { context in
                let t = context.subject
                return t.m11.isFinite && t.m12.isFinite && t.m13.isFinite &&
                       t.m21.isFinite && t.m22.isFinite && t.m23.isFinite &&
                       t.m31.isFinite && t.m32.isFinite && t.m33.isFinite
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
    
    /// Validates that a rectangle's dimensions are finite.
    public static var rectIsFinite: Validation<Document, Rect> {
        .init(
            description: "Rectangle dimensions are finite",
            check: { context in
                context.subject.width.isFinite && context.subject.height.isFinite
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
    
    /// Validates that a path has a valid structure.
    /// A path must start with a move operation, and control points for Bézier curves
    /// must not overlap in a way that collapses the curve to a single point.
    public static var pathStructureIsValid: Validation<Document, Path> {
        .init(
            description: "Path has valid structure and geometry",
            check: { context in
                var errors: [ValidationError] = []
                let elements = context.subject.elements
                
                guard !elements.isEmpty else {
                    return []
                }
                
                // 1. Path must start with a move operation
                if case .move = elements[0] {
                    // OK
                } else {
                    errors.append(ValidationError(
                        reason: "Path must start with a move operation",
                        at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(0)]
                    ))
                }
                
                var currentPoint: Point? = nil
                var subpathStart: Point? = nil
                
                for (index, element) in elements.enumerated() {
                    switch element {
                    case .move(let to):
                        currentPoint = to
                        subpathStart = to
                    case .line(let to):
                        if currentPoint == nil {
                            errors.append(ValidationError(
                                reason: "Line operation at index \(index) occurs before any move operation",
                                at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)]
                            ))
                        }
                        currentPoint = to
                    case .quadCurve(let to, let control):
                        if let start = currentPoint {
                            if start == to && start == control {
                                errors.append(ValidationError(
                                    reason: "Quadratic curve at index \(index) is singular (all control points and endpoints are identical)",
                                    at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)]
                                ))
                            }
                        } else {
                            errors.append(ValidationError(
                                reason: "Quadratic curve operation at index \(index) occurs before any move operation",
                                at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)]
                            ))
                        }
                        currentPoint = to
                    case .cubicCurve(let to, let control1, let control2):
                        if let start = currentPoint {
                            if start == to && start == control1 && start == control2 {
                                errors.append(ValidationError(
                                    reason: "Cubic curve at index \(index) is singular (all control points and endpoints are identical)",
                                    at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)]
                                ))
                            }
                        } else {
                            errors.append(ValidationError(
                                reason: "Cubic curve operation at index \(index) occurs before any move operation",
                                at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)]
                            ))
                        }
                        currentPoint = to
                    case .close:
                        if currentPoint == nil {
                            errors.append(ValidationError(
                                reason: "Close operation at index \(index) occurs before any move operation",
                                at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)]
                            ))
                        }
                        currentPoint = subpathStart
                    }
                }
                
                return errors
            }
        )
    }
}
