//
//  GraphicState.swift
//  PureDraw
//

/// Encapsulates the configuration of styles, coordinate transformation, and clipping for drawing operations.
public struct GraphicState: Equatable, Sendable, Validatable {
    /// The Current Transformation Matrix (CTM).
    public var transform: AffineTransform
    
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
    
    public init(
        transform: AffineTransform = .identity,
        strokeColor: Color = .black,
        fillColor: Color = .black,
        lineWidth: Double = 1.0,
        lineCap: LineCap = .butt,
        lineJoin: LineJoin = .miter,
        miterLimit: Double = 10.0,
        dashPattern: [Double] = [],
        dashPhase: Double = 0.0,
        alpha: Double = 1.0,
        blendMode: BlendMode = .normal,
        clipPath: Path? = nil
    ) {
        self.transform = transform
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dashPattern = dashPattern
        self.dashPhase = dashPhase
        self.alpha = alpha
        self.blendMode = blendMode
        self.clipPath = clipPath
    }
    
    public static var defaultValidator: Validator<GraphicState> {
        Validator().validating(.graphicStateIsValid)
    }
}
