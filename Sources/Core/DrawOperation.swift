//
//  DrawOperation.swift
//  PureDraw
//

import Geometry
import Validation

/// Represents an immutable, recorded drawing command that binds geometry with its drawing state.
public struct DrawOperation: Equatable, Sendable, Validatable {
    public enum Kind: Equatable, Sendable {
        case fill(Path, rule: FillRule)
        case stroke(Path)
        case drawLinearGradient(Gradient, start: Point, end: Point, options: GradientDrawingOptions)
        case drawRadialGradient(Gradient, startCenter: Point, startRadius: Double, endCenter: Point, endRadius: Double, options: GradientDrawingOptions)
        /// An angular (conic / sweep) gradient: the stops sweep around `center` starting from
        /// `startAngle` (radians, clockwise from the positive x-axis) through a full turn, the
        /// angle mapped to the gradient's `[0, 1]` location. Mirrors CSS `conic-gradient` and
        /// `CanvasRenderingContext2D.createConicGradient`.
        case drawConicGradient(Gradient, center: Point, startAngle: Double, options: GradientDrawingOptions)
        case beginTransparencyLayer
        case endTransparencyLayer
        case drawImage(Image, rect: Rect)
        /// Casts the drop shadow of `path`'s silhouette using the current shadow
        /// state, without painting the path itself. The analog of
        /// `CALayer.shadowPath`: a shadow whose shape is given explicitly instead of
        /// derived from the alpha of rendered content.
        case dropShadow(Path)
        /// Draws `image` (placed in `rect`) warped onto a device-space quad through
        /// `transform`, a projective (perspective) texture map. Unlike `drawImage`,
        /// which transforms `rect` by the affine CTM, this carries the complete
        /// rect-to-device projective mapping, so it can render a 3D-projected quad.
        case drawImageProjective(Image, rect: Rect, transform: ProjectiveTransform)
        case drawLayer(Layer, rect: Rect)
        case showText(glyphs: [Int], text: String?, font: Font, fontSize: Double, drawingMode: TextDrawingMode, textMatrix: AffineTransform, position: Point)
    }

    public let kind: Kind
    public let state: GraphicState

    public init(kind: Kind, state: GraphicState) {
        self.kind = kind
        self.state = state
    }

    public static var defaultValidator: Validator<DrawOperation> {
        Validator()
            .validating(.drawOperationPathIsNotEmpty)
            .validating(.linearGradientPointsAreDistinct)
            .validating(.radialGradientIsValid)
            .validating(.drawImageProjectiveIsValid)
            .validating(.drawLayerHasValidDimensions)
            .validating(.showTextIsValid)
    }
}
