//
//  Shadow.swift
//  PureDraw
//

import Geometry
import Validation

/// Represents a drawing shadow with an offset, blur, and color.
public struct Shadow: Equatable, Sendable, Validatable {
    /// The shadow's displacement from the shape that casts it.
    public var offset: Point
    /// The Gaussian blur radius; 0 is a hard-edged shadow.
    public var blur: Double
    /// The shadow color, including its opacity.
    public var color: Color

    /// Creates a shadow from its offset, blur radius, and color.
    public init(offset: Point, blur: Double, color: Color) {
        self.offset = offset
        self.blur = blur
        self.color = color
    }

    /// Validates that the offset and blur are finite and the blur is non-negative.
    public static var defaultValidator: Validator<Shadow> {
        Validator().validating(.shadowIsValid)
    }
}
