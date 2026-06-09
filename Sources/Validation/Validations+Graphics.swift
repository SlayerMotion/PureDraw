//
//  Validations+Graphics.swift
//  PureDraw
//

extension Validation {
    /// Validates that a color's RGBA components are all within the valid range 0.0 ... 1.0.
    public static var colorIsValid: Validation<Document, Color> {
        .init(
            description: "Color components are within 0.0 and 1.0",
            check: { context in
                let c = context.subject
                return (0.0...1.0).contains(c.red) &&
                       (0.0...1.0).contains(c.green) &&
                       (0.0...1.0).contains(c.blue) &&
                       (0.0...1.0).contains(c.alpha)
            }
        )
    }
    
    /// Validates that a graphic state's configuration is mathematically and physically valid.
    public static var graphicStateIsValid: Validation<Document, GraphicState> {
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
                
                if !(0.0...1.0).contains(s.alpha) {
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
                
                // Validate transform using determinant
                if s.transform.determinant == 0 {
                    errors.append(ValidationError(
                        reason: "Transform matrix is singular (non-invertible)",
                        at: context.codingPath + [ValidationCodingKey("transform")]
                    ))
                }
                
                // Validate colors
                let strokeColorValid = (0.0...1.0).contains(s.strokeColor.red) &&
                                       (0.0...1.0).contains(s.strokeColor.green) &&
                                       (0.0...1.0).contains(s.strokeColor.blue) &&
                                       (0.0...1.0).contains(s.strokeColor.alpha)
                if !strokeColorValid {
                    errors.append(ValidationError(
                        reason: "strokeColor components must be between 0.0 and 1.0",
                        at: context.codingPath + [ValidationCodingKey("strokeColor")]
                    ))
                }
                
                let fillColorValid = (0.0...1.0).contains(s.fillColor.red) &&
                                     (0.0...1.0).contains(s.fillColor.green) &&
                                     (0.0...1.0).contains(s.fillColor.blue) &&
                                     (0.0...1.0).contains(s.fillColor.alpha)
                if !fillColorValid {
                    errors.append(ValidationError(
                        reason: "fillColor components must be between 0.0 and 1.0",
                        at: context.codingPath + [ValidationCodingKey("fillColor")]
                    ))
                }
                
                return errors
            }
        )
    }
    
    /// Validates that a gradient stop has its location in the normalized 0.0 ... 1.0 range.
    public static var gradientStopIsValid: Validation<Document, GradientStop> {
        .init(
            description: "Gradient stop location is between 0.0 and 1.0",
            check: { context in
                (0.0...1.0).contains(context.subject.location)
            }
        )
    }
    
    /// Validates that a gradient contains at least two stops.
    public static var gradientIsValid: Validation<Document, Gradient> {
        .init(
            description: "Gradient contains at least two stops",
            check: { context in
                context.subject.stops.count >= 2
            }
        )
    }
    
    /// Validates that a shadow configuration is valid (e.g. non-negative blur).
    public static var shadowIsValid: Validation<Document, Shadow> {
        .init(
            description: "Shadow blur radius is non-negative",
            check: { context in
                context.subject.blur >= 0
            }
        )
    }
}

