//
//  GradientStop.swift
//  PureDraw
//

import Validation

/// A color stop in a gradient, defining a color at a specific normalized offset.
public struct GradientStop: Equatable, Sendable, Validatable {
    /// The color at this stop.
    public var color: Color
    /// The stop's position along the gradient, normalized to 0...1.
    public var location: Double

    /// Creates a gradient stop from a color and a normalized location.
    public init(color: Color, location: Double) {
        self.color = color
        self.location = location
    }

    /// Validates that the location is finite and within 0...1.
    public static var defaultValidator: Validator<GradientStop> {
        Validator().validating(.gradientStopIsValid)
    }
}
