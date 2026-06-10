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
                for comp in context.subject.components {
                    if !(0.0 ... 1.0).contains(comp) {
                        return false
                    }
                }
                return true
            }
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
                        at: context.codingPath + [ValidationCodingKey("lineWidth")]
                    ))
                }

                if s.miterLimit < 0 {
                    errors.append(ValidationError(
                        reason: "miterLimit cannot be negative",
                        at: context.codingPath + [ValidationCodingKey("miterLimit")]
                    ))
                }

                if s.flatness < 0 {
                    errors.append(ValidationError(
                        reason: "flatness cannot be negative",
                        at: context.codingPath + [ValidationCodingKey("flatness")]
                    ))
                }

                if !(0.0 ... 1.0).contains(s.alpha) {
                    errors.append(ValidationError(
                        reason: "alpha must be between 0.0 and 1.0",
                        at: context.codingPath + [ValidationCodingKey("alpha")]
                    ))
                }

                for (index, dash) in s.dashPattern.enumerated() {
                    if dash < 0 {
                        errors.append(ValidationError(
                            reason: "dashPattern element at index \(index) cannot be negative",
                            at: context.codingPath + [ValidationCodingKey("dashPattern"), ValidationCodingKey(index)]
                        ))
                    }
                }

                if !s.dashPattern.isEmpty {
                    let sum = s.dashPattern.reduce(0.0, +)
                    if sum <= 0 {
                        errors.append(ValidationError(
                            reason: "dashPattern cannot consist of only zero lengths",
                            at: context.codingPath + [ValidationCodingKey("dashPattern")]
                        ))
                    }
                }

                // Validate transform using determinant
                if s.transform.determinant == 0 {
                    errors.append(ValidationError(
                        reason: "Transform matrix is singular (non-invertible)",
                        at: context.codingPath + [ValidationCodingKey("transform")]
                    ))
                }

                // Validate colors
                let strokeColorValid = s.strokeColor.components.allSatisfy { (0.0 ... 1.0).contains($0) }
                if !strokeColorValid {
                    errors.append(ValidationError(
                        reason: "strokeColor components must be between 0.0 and 1.0",
                        at: context.codingPath + [ValidationCodingKey("strokeColor")]
                    ))
                }

                let fillColorValid = s.fillColor.components.allSatisfy { (0.0 ... 1.0).contains($0) }
                if !fillColorValid {
                    errors.append(ValidationError(
                        reason: "fillColor components must be between 0.0 and 1.0",
                        at: context.codingPath + [ValidationCodingKey("fillColor")]
                    ))
                }

                if s.fontSize < 0 {
                    errors.append(ValidationError(
                        reason: "fontSize cannot be negative",
                        at: context.codingPath + [ValidationCodingKey("fontSize")]
                    ))
                }

                if s.maskImage != nil {
                    if s.maskRect == nil {
                        errors.append(ValidationError(
                            reason: "maskRect must be set when maskImage is present",
                            at: context.codingPath + [ValidationCodingKey("maskRect")]
                        ))
                    }
                    if s.maskTransform == nil {
                        errors.append(ValidationError(
                            reason: "maskTransform must be set when maskImage is present",
                            at: context.codingPath + [ValidationCodingKey("maskTransform")]
                        ))
                    }
                }

                return errors
            }
        )
    }

    /// Validates that a gradient stop has its location in the normalized 0.0 ... 1.0 range.
    static var gradientStopIsValid: Validation<Document, GradientStop> {
        .init(
            description: "Gradient stop location is between 0.0 and 1.0",
            check: { context in
                (0.0 ... 1.0).contains(context.subject.location)
            }
        )
    }

    /// Validates that a gradient contains at least two stops.
    static var gradientIsValid: Validation<Document, Gradient> {
        .init(
            description: "Gradient contains at least two stops",
            check: { context in
                context.subject.stops.count >= 2
            }
        )
    }

    /// Validates that a shadow configuration is valid (e.g. non-negative blur).
    static var shadowIsValid: Validation<Document, Shadow> {
        .init(
            description: "Shadow blur radius is non-negative",
            check: { context in
                context.subject.blur >= 0
            }
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
                            at: context.codingPath + [ValidationCodingKey("kind")]
                        )]
                    }
                case .drawLinearGradient, .drawRadialGradient, .beginTransparencyLayer, .endTransparencyLayer, .drawImage, .drawLayer:
                    break
                }
                return []
            }
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
                            at: context.codingPath + [ValidationCodingKey("kind")]
                        )]
                    }
                }
                return []
            }
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
                            at: context.codingPath + [ValidationCodingKey("kind"), ValidationCodingKey("startRadius")]
                        ))
                    }
                    if endRadius < 0 {
                        errors.append(ValidationError(
                            reason: "Radial gradient end radius cannot be negative",
                            at: context.codingPath + [ValidationCodingKey("kind"), ValidationCodingKey("endRadius")]
                        ))
                    }
                    if startCenter == endCenter, startRadius == endRadius {
                        errors.append(ValidationError(
                            reason: "Radial gradient start and end circles cannot be identical",
                            at: context.codingPath + [ValidationCodingKey("kind")]
                        ))
                    }
                    return errors
                }
                return []
            }
        )
    }

    /// Validates that an image's dimensions, bits, and bytes are valid and matches data buffer size.
    static var imageIsValid: Validation<Document, Image> {
        .init(
            description: "Image dimensions and data are valid",
            check: { context in
                var errors: [ValidationError] = []
                let img = context.subject

                if img.width <= 0 {
                    errors.append(ValidationError(
                        reason: "width must be positive",
                        at: context.codingPath + [ValidationCodingKey("width")]
                    ))
                }

                if img.height <= 0 {
                    errors.append(ValidationError(
                        reason: "height must be positive",
                        at: context.codingPath + [ValidationCodingKey("height")]
                    ))
                }

                if img.bitsPerComponent != 8 {
                    errors.append(ValidationError(
                        reason: "bitsPerComponent must be 8; pixel decoding supports no other component depth yet",
                        at: context.codingPath + [ValidationCodingKey("bitsPerComponent")]
                    ))
                }

                if img.bitsPerPixel <= 0 {
                    errors.append(ValidationError(
                        reason: "bitsPerPixel must be positive",
                        at: context.codingPath + [ValidationCodingKey("bitsPerPixel")]
                    ))
                }

                if img.bytesPerRow <= 0 {
                    errors.append(ValidationError(
                        reason: "bytesPerRow must be positive",
                        at: context.codingPath + [ValidationCodingKey("bytesPerRow")]
                    ))
                }

                let minBytes = img.height * img.bytesPerRow
                if img.data.count < minBytes {
                    errors.append(ValidationError(
                        reason: "data buffer size is smaller than height * bytesPerRow",
                        at: context.codingPath + [ValidationCodingKey("data")]
                    ))
                }

                if let maskingColors = img.maskingColors {
                    if img.alphaInfo.hasAlpha {
                        errors.append(ValidationError(
                            reason: "maskingColors requires an image without an alpha channel (alphaInfo .none, .noneSkipLast, or .noneSkipFirst)",
                            at: context.codingPath + [ValidationCodingKey("maskingColors")]
                        ))
                    }
                    let expectedCount = switch img.colorSpace {
                    case .deviceRGB: 6
                    case .deviceGray: 2
                    case .deviceCMYK: 8
                    }
                    if maskingColors.count != expectedCount {
                        errors.append(ValidationError(
                            reason: "maskingColors count must be \(expectedCount) for colorSpace \(img.colorSpace.rawValue)",
                            at: context.codingPath + [ValidationCodingKey("maskingColors")]
                        ))
                    }
                    for (index, val) in maskingColors.enumerated() {
                        if !(0.0 ... 1.0).contains(val) {
                            errors.append(ValidationError(
                                reason: "maskingColors element at index \(index) must be between 0.0 and 1.0",
                                at: context.codingPath + [ValidationCodingKey("maskingColors"), ValidationCodingKey(index)]
                            ))
                        }
                    }
                }

                return errors
            }
        )
    }
}
