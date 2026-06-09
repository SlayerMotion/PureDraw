//
//  Color.swift
//  PureDraw
//

import Validation

/// A representation of a color using red, green, blue, and alpha components.
public struct Color: Equatable, Sendable, Validatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public static let black = Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    public static let white = Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    public static let clear = Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static var defaultValidator: Validator<Color> {
        Validator().validating(.colorIsValid)
    }
}
