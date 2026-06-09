import PureGeometry
import PureValidation

//
//  Validations+Geometry.swift
//  PureDraw
//

public extension Validation {
    /// Validates that a path has a valid structure.
    /// A path must start with a move operation, and control points for Bézier curves
    /// must not overlap in a way that collapses the curve to a single point.
    static var pathStructureIsValid: Validation<Document, Path> {
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
                        at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(0)],
                    ))
                }

                var currentPoint: Point? = nil
                var subpathStart: Point? = nil

                for (index, element) in elements.enumerated() {
                    switch element {
                    case let .move(to):
                        currentPoint = to
                        subpathStart = to
                    case let .line(to):
                        if currentPoint == nil {
                            errors.append(ValidationError(
                                reason: "Line operation at index \(index) occurs before any move operation",
                                at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)],
                            ))
                        }
                        currentPoint = to
                    case let .quadCurve(to, control):
                        if let start = currentPoint {
                            if start == to, start == control {
                                errors.append(ValidationError(
                                    reason: "Quadratic curve at index \(index) is singular (all control points and endpoints are identical)",
                                    at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)],
                                ))
                            }
                        } else {
                            errors.append(ValidationError(
                                reason: "Quadratic curve operation at index \(index) occurs before any move operation",
                                at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)],
                            ))
                        }
                        currentPoint = to
                    case let .cubicCurve(to, control1, control2):
                        if let start = currentPoint {
                            if start == to, start == control1, start == control2 {
                                errors.append(ValidationError(
                                    reason: "Cubic curve at index \(index) is singular (all control points and endpoints are identical)",
                                    at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)],
                                ))
                            }
                        } else {
                            errors.append(ValidationError(
                                reason: "Cubic curve operation at index \(index) occurs before any move operation",
                                at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)],
                            ))
                        }
                        currentPoint = to
                    case .close:
                        if currentPoint == nil {
                            errors.append(ValidationError(
                                reason: "Close operation at index \(index) occurs before any move operation",
                                at: context.codingPath + [ValidationCodingKey("elements"), ValidationCodingKey(index)],
                            ))
                        }
                        currentPoint = subpathStart
                    }
                }

                return errors
            },
        )
    }
}
