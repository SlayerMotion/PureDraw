//
//  Shadow.swift
//  PureDraw
//

import PureGeometry
import PureValidation

/// Represents a drawing shadow with an offset, blur, and color.
public struct Shadow: Equatable, Sendable, Validatable {
    public var offset: Point
    public var blur: Double
    public var color: Color

    public init(offset: Point, blur: Double, color: Color) {
        self.offset = offset
        self.blur = blur
        self.color = color
    }

    public static var defaultValidator: Validator<Shadow> {
        Validator().validating(.shadowIsValid)
    }
}
