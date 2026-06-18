//
//  Gradient.swift
//  PureDraw
//

import Validation

/// Represents a linear or radial color gradient.
public struct Gradient: Equatable, Sendable, Validatable {
    /// The color stops, in ascending location order, that define the gradient.
    public var stops: [GradientStop]

    /// Creates a gradient from its color stops.
    public init(stops: [GradientStop]) {
        self.stops = stops
    }

    /// Validates that the stops are well formed and their locations are in range.
    public static var defaultValidator: Validator<Gradient> {
        Validator().validating(.gradientIsValid)
    }
}

public extension Gradient {
    /// Builds a gradient from a procedural color function, the `CGFunction`
    /// shading equivalent. The function is sampled at `samples` evenly spaced
    /// parameters in `0...1`, so the result is an ordinary stop gradient that
    /// every backend renders without special support, exactly as CoreGraphics
    /// samples a shading function internally.
    init(samples: Int = 256, _ shading: (_ t: Double) -> Color) {
        let count = max(2, samples)
        var stops: [GradientStop] = []
        stops.reserveCapacity(count)
        for index in 0 ..< count {
            let t = Double(index) / Double(count - 1)
            stops.append(GradientStop(color: shading(t), location: t))
        }
        self.init(stops: stops)
    }
}
