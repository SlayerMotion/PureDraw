//
//  Color.swift
//  PureDraw
//

import Validation

/// A representation of a color using red, green, blue, and alpha components.
public struct Color: Equatable, Sendable, Validatable {
    public private(set) var colorSpace: ColorSpace
    public private(set) var components: [Double]

    /// Opaque black.
    public static let black = Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    /// Opaque white.
    public static let white = Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    /// Fully transparent.
    public static let clear = Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

    /// Creates an RGB color from components in the range 0...1.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        colorSpace = .deviceRGB
        components = [red, green, blue, alpha]
    }

    /// Creates a grayscale color from a gray value in the range 0...1.
    public init(gray: Double, alpha: Double = 1.0) {
        colorSpace = .deviceGray
        components = [gray, alpha]
    }

    /// Creates a CMYK color from components in the range 0...1.
    public init(cyan: Double, magenta: Double, yellow: Double, black: Double, alpha: Double = 1.0) {
        colorSpace = .deviceCMYK
        components = [cyan, magenta, yellow, black, alpha]
    }

    /// The red component in the range 0...1, converted from the color's space.
    public var red: Double {
        get {
            switch colorSpace {
            case .deviceRGB:
                components[0]
            case .deviceGray:
                components[0]
            case .deviceCMYK:
                (1.0 - components[0]) * (1.0 - components[3])
            }
        }
        set {
            convertToRGB()
            components[0] = newValue
        }
    }

    /// The green component in the range 0...1, converted from the color's space.
    public var green: Double {
        get {
            switch colorSpace {
            case .deviceRGB:
                components[1]
            case .deviceGray:
                components[0]
            case .deviceCMYK:
                (1.0 - components[1]) * (1.0 - components[3])
            }
        }
        set {
            convertToRGB()
            components[1] = newValue
        }
    }

    /// The blue component in the range 0...1, converted from the color's space.
    public var blue: Double {
        get {
            switch colorSpace {
            case .deviceRGB:
                components[2]
            case .deviceGray:
                components[0]
            case .deviceCMYK:
                (1.0 - components[2]) * (1.0 - components[3])
            }
        }
        set {
            convertToRGB()
            components[2] = newValue
        }
    }

    /// The alpha (opacity) component in the range 0...1.
    public var alpha: Double {
        get {
            switch colorSpace {
            case .deviceRGB:
                components[3]
            case .deviceGray:
                components[1]
            case .deviceCMYK:
                components[4]
            }
        }
        set {
            switch colorSpace {
            case .deviceRGB:
                components[3] = newValue
            case .deviceGray:
                components[1] = newValue
            case .deviceCMYK:
                components[4] = newValue
            }
        }
    }

    private mutating func convertToRGB() {
        if colorSpace == .deviceRGB { return }
        let r = red
        let g = green
        let b = blue
        let a = alpha
        colorSpace = .deviceRGB
        components = [r, g, b, a]
    }

    /// Validates that every component is finite and within 0...1.
    public static var defaultValidator: Validator<Color> {
        Validator().validating(.colorIsValid)
    }
}
