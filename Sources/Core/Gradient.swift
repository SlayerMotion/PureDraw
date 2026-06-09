//
//  Gradient.swift
//  PureDraw
//

import Validation

/// Represents a linear or radial color gradient.
public struct Gradient: Equatable, Sendable, Validatable {
    public var stops: [GradientStop]

    public init(stops: [GradientStop]) {
        self.stops = stops
    }

    public static var defaultValidator: Validator<Gradient> {
        Validator().validating(.gradientIsValid)
    }
}
