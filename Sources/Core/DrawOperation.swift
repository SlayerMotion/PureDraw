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
        case beginTransparencyLayer
        case endTransparencyLayer
        case drawImage(Image, rect: Rect)
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
            .validating(.drawLayerHasValidDimensions)
            .validating(.showTextIsValid)
    }
}
