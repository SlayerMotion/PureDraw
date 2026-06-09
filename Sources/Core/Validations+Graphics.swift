import Geometry
import Validation

//
//  Validations+Graphics.swift
//  PureDraw
//

public extension Validation {
    /// Validates that a color's RGBA components are all within the valid range 0.0 ... 1.0.
    static var colorIsValid: Validation<Document, Color> {
        .init(
            description: "Color components are within 0.0 and 1.0",
            check: { context in
                let c = context.subject
                return (0.0 ... 1.0).contains(c.red) &&
                    (0.0 ... 1.0).contains(c.green) &&
                    (0.0 ... 1.0).contains(c.blue) &&
                    (0.0 ... 1.0).contains(c.alpha)
            },
        )
    }

    /// Validates that a graphic state's configuration is mathematically and physically valid.
    static var graphicStateIsValid: Validation<Document, GraphicState> {
        .init(
            description: "Graphic state properties are valid",
            check: { context in
                var errors: [ValidationError] = []
                let s = context.subject

                if s.lineWidth < 0 {
                    errors.append(ValidationError(
                        reason: "lineWidth cannot be negative",
                        at: context.codingPath + [ValidationCodingKey("lineWidth")],
                    ))
                }

                if s.miterLimit < 0 {
                    errors.append(ValidationError(
                        reason: "miterLimit cannot be negative",
                        at: context.codingPath + [ValidationCodingKey("miterLimit")],
                    ))
                }

                if !(0.0 ... 1.0).contains(s.alpha) {
                    errors.append(ValidationError(
                        reason: "alpha must be between 0.0 and 1.0",
                        at: context.codingPath + [ValidationCodingKey("alpha")],
                    ))
                }

                for (index, dash) in s.dashPattern.enumerated() {
                    if dash < 0 {
                        errors.append(ValidationError(
                            reason: "dashPattern element at index \(index) cannot be negative",
                            at: context.codingPath + [ValidationCodingKey("dashPattern"), ValidationCodingKey(index)],
                        ))
                    }
                }

                if !s.dashPattern.isEmpty {
                    let sum = s.dashPattern.reduce(0.0, +)
                    if sum <= 0 {
                        errors.append(ValidationError(
                            reason: "dashPattern cannot consist of only zero lengths",
                            at: context.codingPath + [ValidationCodingKey("dashPattern")],
                        ))
                    }
                }

                // Validate transform using determinant
                if s.transform.determinant == 0 {
                    errors.append(ValidationError(
                        reason: "Transform matrix is singular (non-invertible)",
                        at: context.codingPath + [ValidationCodingKey("transform")],
                    ))
                }

                // Validate colors
                let strokeColorValid = (0.0 ... 1.0).contains(s.strokeColor.red) &&
                    (0.0 ... 1.0).contains(s.strokeColor.green) &&
                    (0.0 ... 1.0).contains(s.strokeColor.blue) &&
                    (0.0 ... 1.0).contains(s.strokeColor.alpha)
                if !strokeColorValid {
                    errors.append(ValidationError(
                        reason: "strokeColor components must be between 0.0 and 1.0",
                        at: context.codingPath + [ValidationCodingKey("strokeColor")],
                    ))
                }

                let fillColorValid = (0.0 ... 1.0).contains(s.fillColor.red) &&
                    (0.0 ... 1.0).contains(s.fillColor.green) &&
                    (0.0 ... 1.0).contains(s.fillColor.blue) &&
                    (0.0 ... 1.0).contains(s.fillColor.alpha)
                if !fillColorValid {
                    errors.append(ValidationError(
                        reason: "fillColor components must be between 0.0 and 1.0",
                        at: context.codingPath + [ValidationCodingKey("fillColor")],
                    ))
                }

                return errors
            },
        )
    }

    /// Validates that a gradient stop has its location in the normalized 0.0 ... 1.0 range.
    static var gradientStopIsValid: Validation<Document, GradientStop> {
        .init(
            description: "Gradient stop location is between 0.0 and 1.0",
            check: { context in
                (0.0 ... 1.0).contains(context.subject.location)
            },
        )
    }

    /// Validates that a gradient contains at least two stops.
    static var gradientIsValid: Validation<Document, Gradient> {
        .init(
            description: "Gradient contains at least two stops",
            check: { context in
                context.subject.stops.count >= 2
            },
        )
    }

    /// Validates that a shadow configuration is valid (e.g. non-negative blur).
    static var shadowIsValid: Validation<Document, Shadow> {
        .init(
            description: "Shadow blur radius is non-negative",
            check: { context in
                context.subject.blur >= 0
            },
        )
    }

    /// Validates that a draw operation's path (if any) is not empty.
    static var drawOperationPathIsNotEmpty: Validation<Document, DrawOperation> {
        .init(
            description: "Draw operation path is not empty",
            check: { context in
                switch context.subject.kind {
                case let .fill(path, _), let .stroke(path):
                    if path.isEmpty {
                        return [ValidationError(
                            reason: "Drawing path cannot be empty",
                            at: context.codingPath + [ValidationCodingKey("kind")],
                        )]
                    }
                case .drawLinearGradient, .drawRadialGradient:
                    break
                }
                return []
            },
        )
    }

    /// Validates that a linear gradient has distinct start and end points.
    static var linearGradientPointsAreDistinct: Validation<Document, DrawOperation> {
        .init(
            description: "Linear gradient start and end points are distinct",
            check: { context in
                if case let .drawLinearGradient(_, start, end, _) = context.subject.kind {
                    if start == end {
                        return [ValidationError(
                            reason: "Linear gradient start and end points cannot be identical",
                            at: context.codingPath + [ValidationCodingKey("kind")],
                        )]
                    }
                }
                return []
            },
        )
    }

    /// Validates that radial gradient radii are non-negative and distinct if centers are identical.
    static var radialGradientIsValid: Validation<Document, DrawOperation> {
        .init(
            description: "Radial gradient configuration is valid",
            check: { context in
                if case let .drawRadialGradient(_, startCenter, startRadius, endCenter, endRadius, _) = context.subject.kind {
                    var errors: [ValidationError] = []
                    if startRadius < 0 {
                        errors.append(ValidationError(
                            reason: "Radial gradient start radius cannot be negative",
                            at: context.codingPath + [ValidationCodingKey("kind"), ValidationCodingKey("startRadius")],
                        ))
                    }
                    if endRadius < 0 {
                        errors.append(ValidationError(
                            reason: "Radial gradient end radius cannot be negative",
                            at: context.codingPath + [ValidationCodingKey("kind"), ValidationCodingKey("endRadius")],
                        ))
                    }
                    if startCenter == endCenter, startRadius == endRadius {
                        errors.append(ValidationError(
                            reason: "Radial gradient start and end circles cannot be identical",
                            at: context.codingPath + [ValidationCodingKey("kind")],
                        ))
                    }
                    return errors
                }
                return []
            },
        )
    }
}
