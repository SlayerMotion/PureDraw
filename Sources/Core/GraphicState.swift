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

    /// The clip paths in effect, outermost first. Clipping is the intersection of
    /// them all: Core Graphics' `clip` intersects the new path with the current
    /// clip, it does not union. Keeping them apart preserves that distinction,
    /// which a single combined path loses.
    public var clipPaths: [Path]

    /// The clip stack appended into a single path: a UNION, not the intersection that
    /// nested clipping actually means. This is retained only for renderers that emit
    /// clips through their own machinery (CoreGraphics/PDF/SVG/Canvas/PostScript clip a
    /// path per op) and for `Layer`/`Pattern` inheritance. `BitmapRenderer` does NOT use
    /// it: it intersects ``clipPaths`` directly for gradients AND for fills/strokes/images
    /// (the latter via `intersectedClipCoverage`), because the once-assumed "self-bounded
    /// content is unaffected by the union" is false for nested clips: a fill inside an
    /// inner clip but outside an outer one floods through the union. WARNING: any consumer
    /// that rasterizes against this union inherits that nested-clip flood; intersect
    /// ``clipPaths`` instead. Setting this replaces the whole stack with one path.
    public var clipPath: Path? {
        get {
            guard !clipPaths.isEmpty else { return nil }
            var combined = Path()
            for path in clipPaths {
                combined.addPath(path)
            }
            return combined
        }
        set { clipPaths = newValue.map { [$0] } ?? [] }
    }

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

    /// The font used by text-showing operations.
    public var font: Font?

    /// The text size in user-space units.
    public var fontSize: Double

    /// Extra spacing added after each shown glyph, in user-space units.
    public var characterSpacing: Double

    /// How shown text is painted.
    public var textDrawingMode: TextDrawingMode

    /// The tiling pattern used by fill operations; nil fills with `fillColor`.
    public var fillPattern: Pattern?

    /// The current active image-based clipping mask.
    public var maskImage: Image?

    /// The target rectangle where the mask image is mapped.
    public var maskRect: Rect?

    /// The transform matrix at the time the mask was set.
    public var maskTransform: Geometry.AffineTransform?

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
        shouldSubpixelQuantizeFonts: Bool = true,
        font: Font? = nil,
        fontSize: Double = 12.0,
        characterSpacing: Double = 0.0,
        textDrawingMode: TextDrawingMode = .fill,
        fillPattern: Pattern? = nil,
        maskImage: Image? = nil,
        maskRect: Rect? = nil,
        maskTransform: Geometry.AffineTransform? = nil
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
        clipPaths = clipPath.map { [$0] } ?? []
        self.shadow = shadow
        self.shouldAntialias = shouldAntialias
        self.allowsAntialiasing = allowsAntialiasing
        self.interpolationQuality = interpolationQuality
        self.renderingIntent = renderingIntent
        self.shouldSmoothFonts = shouldSmoothFonts
        self.allowsFontSmoothing = allowsFontSmoothing
        self.shouldSubpixelPositionFonts = shouldSubpixelPositionFonts
        self.shouldSubpixelQuantizeFonts = shouldSubpixelQuantizeFonts
        self.font = font
        self.fontSize = fontSize
        self.characterSpacing = characterSpacing
        self.textDrawingMode = textDrawingMode
        self.fillPattern = fillPattern
        self.maskImage = maskImage
        self.maskRect = maskRect
        self.maskTransform = maskTransform
    }

    public static var defaultValidator: Validator<GraphicState> {
        Validator().validating(.graphicStateIsValid)
    }
}
