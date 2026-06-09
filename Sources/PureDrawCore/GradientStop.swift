//
//  GradientStop.swift
//  PureDraw
//

import PureValidation

/// A color stop in a gradient, defining a color at a specific normalized offset.
public struct GradientStop: Equatable, Sendable, Validatable {
    public var color: Color
    public var location: Double

    public init(color: Color, location: Double) {
        self.color = color
        self.location = location
    }

    public static var defaultValidator: Validator<GradientStop> {
        Validator().validating(.gradientStopIsValid)
    }
}
