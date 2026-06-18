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
                    // Reject NaN/Inf explicitly (a range check alone relies on the
                    // incidental fact that `contains(NaN)` is false).
                    if !comp.isFinite || !(0.0 ... 1.0).contains(comp) {
                        return false
                    }
                }
                return true
            }
        )
    }

    /// Validates that a pattern's cell bounds and tiling steps are finite and positive.
    /// A zero/negative/non-finite step (the default is `bounds.width`/`height`, so an
    /// invalid `bounds` propagates) tiles degenerately or risks divide-by-zero downstream.
    static var patternIsValid: Validation<Document, Pattern> {
        .init(
            description: "Pattern bounds are finite with positive size and tiling steps",
            check: { context in
                let p = context.subject
                return p.bounds.origin.x.isFinite && p.bounds.origin.y.isFinite
                    && p.bounds.width.isFinite && p.bounds.height.isFinite
                    && p.bounds.width > 0 && p.bounds.height > 0
                    && p.xStep.isFinite && p.yStep.isFinite && p.xStep > 0 && p.yStep > 0
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

                // A pattern's bounds are validated via the embedded Rect, but
                // its step values are bare Doubles that escape reflection.
                if let pattern = s.fillPattern, pattern.xStep <= 0 || pattern.yStep <= 0 {
                    errors.append(ValidationError(
                        reason: "fillPattern xStep and yStep must be positive",
                        at: context.codingPath + [ValidationCodingKey("fillPattern")]
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
                // Explicit finite check (a range check alone relies on contains(NaN)==false).
                context.subject.location.isFinite && (0.0 ... 1.0).contains(context.subject.location)
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
                case .drawLinearGradient, .drawRadialGradient, .drawConicGradient, .beginTransparencyLayer, .endTransparencyLayer,
                     .drawImage, .drawImageProjective, .dropShadow, .drawLayer, .showText:
                    // An empty shadow path simply casts no shadow, like an empty fill.
                    break
                }
                return []
            }
        )
    }

    /// Validates that a layer-stamp operation has positive layer dimensions.
    static var drawLayerHasValidDimensions: Validation<Document, DrawOperation> {
        .init(
            description: "Layer stamp has positive dimensions",
            check: { context in
                guard case let .drawLayer(layer, _) = context.subject.kind else { return [] }
                guard layer.width > 0, layer.height > 0 else {
                    return [ValidationError(
                        reason: "Layer width and height must be positive",
                        at: context.codingPath + [ValidationCodingKey("kind")]
                    )]
                }
                return []
            }
        )
    }

    /// Validates a text-show operation's captured scalars: the font size must
    /// be non-negative and glyph indices non-negative. The text matrix and
    /// position are validated through reflection.
    static var showTextIsValid: Validation<Document, DrawOperation> {
        .init(
            description: "Text-show operation parameters are valid",
            check: { context in
                guard case let .showText(glyphs, _, _, fontSize, _, _, _) = context.subject.kind else { return [] }
                var errors: [ValidationError] = []
                if fontSize < 0 {
                    errors.append(ValidationError(
                        reason: "showText fontSize cannot be negative",
                        at: context.codingPath + [ValidationCodingKey("kind"), ValidationCodingKey("fontSize")]
                    ))
                }
                if glyphs.contains(where: { $0 < 0 }) {
                    errors.append(ValidationError(
                        reason: "showText glyph indices cannot be negative",
                        at: context.codingPath + [ValidationCodingKey("kind"), ValidationCodingKey("glyphs")]
                    ))
                }
                return errors
            }
        )
    }

    /// Validates that begin/end transparency-layer operations balance, so
    /// renderers never emit an unclosed group or drop an unmatched end.
    static var transparencyLayersAreBalanced: Validation<Document, GraphicsContext> {
        .init(
            description: "Transparency layers are balanced",
            check: { context in
                var depth = 0
                for op in context.subject.commands {
                    switch op.kind {
                    case .beginTransparencyLayer:
                        depth += 1
                    case .endTransparencyLayer:
                        depth -= 1
                        if depth < 0 {
                            return [ValidationError(
                                reason: "endTransparencyLayer without a matching beginTransparencyLayer",
                                at: context.codingPath + [ValidationCodingKey("commands")]
                            )]
                        }
                    default:
                        break
                    }
                }
                guard depth == 0 else {
                    return [ValidationError(
                        reason: "\(depth) transparency layer(s) opened but never closed",
                        at: context.codingPath + [ValidationCodingKey("commands")]
                    )]
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

    /// Validates that a projective image draw's transform is invertible and finite,
    /// so the image can actually be mapped onto its quad; a singular or non-finite
    /// transform renders nothing. Delegates to the transform's own rules, which is
    /// where invertibility and finiteness are authoritatively defined.
    static var drawImageProjectiveIsValid: Validation<Document, DrawOperation> {
        .init(
            description: "Projective image transform is invertible and finite",
            check: { context in
                guard case let .drawImageProjective(_, _, transform) = context.subject.kind else { return [] }
                return transform.runDefaultValidator(
                    at: context.codingPath + [ValidationCodingKey("kind"), ValidationCodingKey("transform")],
                    in: transform
                )
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

                // bitsPerPixel must hold every component plus any alpha byte,
                // or pixelColor decodes the wrong layout (often as clear).
                let componentCount = switch img.colorSpace {
                case .deviceGray: 1
                case .deviceRGB: 3
                case .deviceCMYK: 4
                }
                let channelCount = componentCount + (img.alphaInfo.hasAlpha ? 1 : 0)
                let minBitsPerPixel = channelCount * img.bitsPerComponent
                if img.bitsPerPixel < minBitsPerPixel {
                    errors.append(ValidationError(
                        reason: "bitsPerPixel must be at least \(minBitsPerPixel) for colorSpace \(img.colorSpace.rawValue) with this alpha layout",
                        at: context.codingPath + [ValidationCodingKey("bitsPerPixel")]
                    ))
                }

                // A declared row narrower than the pixels it must hold decodes
                // bytes from the following row.
                let minBytesPerRow = (img.width * img.bitsPerPixel + 7) / 8
                if img.bytesPerRow < minBytesPerRow {
                    errors.append(ValidationError(
                        reason: "bytesPerRow must be at least \(minBytesPerRow) for width \(img.width) at \(img.bitsPerPixel) bits per pixel",
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
