//
//  GraphicState.swift
//  PureDraw
//

import Geometry
import Validation

/// Encapsulates the configuration of styles, coordinate transformation, and clipping for drawing operations.
public struct GraphicState: Equatable, Sendable, Validatable {
    /// The Current Transformation Matrix (CTM).
    public var transform: Geometry.AffineTransform

    /// The color used when stroking a path.
    public var strokeColor: Color

    /// The color used when filling a path.
    public var fillColor: Color

    /// The width of stroked lines.
    public var lineWidth: Double

    /// The line cap style for stroked lines.
    public var lineCap: LineCap

    /// The line join style for stroked path joints.
    public var lineJoin: LineJoin

    /// The limit for miter joins.
    public var miterLimit: Double

    /// The accuracy of curve rendering.
    public var flatness: Double

    /// The dash lengths for strokes. An empty array indicates a solid line.
    public var dashPattern: [Double]

    /// The phase offset at which to start the dash pattern.
    public var dashPhase: Double

    /// The opacity multiplier (0.0 to 1.0).
    public var alpha: Double

    /// The blend mode.
    public var blendMode: BlendMode

    /// The current accumulated clipping path.
    public var clipPath: Path?

    /// The shadow properties to apply to drawing operations.
    public var shadow: Shadow?

    /// Whether anti-aliasing is enabled for this state.
    public var shouldAntialias: Bool

    /// Whether anti-aliasing is allowed for the context.
    public var allowsAntialiasing: Bool

    /// The interpolation quality to use when scaling images.
    public var interpolationQuality: InterpolationQuality

    /// The rendering intent for color space mappings.
    public var renderingIntent: RenderingIntent

    /// Whether font smoothing is enabled.
    public var shouldSmoothFonts: Bool

    /// Whether font smoothing is allowed.
    public var allowsFontSmoothing: Bool

    /// Whether to position fonts at subpixel coordinates.
    public var shouldSubpixelPositionFonts: Bool

    /// Whether to quantize fonts at subpixel positions.
    public var shouldSubpixelQuantizeFonts: Bool

    public init(
        transform: Geometry.AffineTransform = .identity,
        strokeColor: Color = .black,
        fillColor: Color = .black,
        lineWidth: Double = 1.0,
        lineCap: LineCap = .butt,
        lineJoin: LineJoin = .miter,
        miterLimit: Double = 10.0,
        flatness: Double = 0.6,
        dashPattern: [Double] = [],
        dashPhase: Double = 0.0,
        alpha: Double = 1.0,
        blendMode: BlendMode = .normal,
        clipPath: Path? = nil,
        shadow: Shadow? = nil,
        shouldAntialias: Bool = true,
        allowsAntialiasing: Bool = true,
        interpolationQuality: InterpolationQuality = .default,
        renderingIntent: RenderingIntent = .default,
        shouldSmoothFonts: Bool = true,
        allowsFontSmoothing: Bool = true,
        shouldSubpixelPositionFonts: Bool = true,
        shouldSubpixelQuantizeFonts: Bool = true
    ) {
        self.transform = transform
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.flatness = flatness
        self.dashPattern = dashPattern
        self.dashPhase = dashPhase
        self.alpha = alpha
        self.blendMode = blendMode
        self.clipPath = clipPath
        self.shadow = shadow
        self.shouldAntialias = shouldAntialias
        self.allowsAntialiasing = allowsAntialiasing
        self.interpolationQuality = interpolationQuality
        self.renderingIntent = renderingIntent
        self.shouldSmoothFonts = shouldSmoothFonts
        self.allowsFontSmoothing = allowsFontSmoothing
        self.shouldSubpixelPositionFonts = shouldSubpixelPositionFonts
        self.shouldSubpixelQuantizeFonts = shouldSubpixelQuantizeFonts
    }

    public static var defaultValidator: Validator<GraphicState> {
        Validator().validating(.graphicStateIsValid)
    }
}
