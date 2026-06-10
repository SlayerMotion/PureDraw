//
//  Color.swift
//  PureDraw
//

import Validation

/// A representation of a color using red, green, blue, and alpha components.
public struct Color: Equatable, Sendable, Validatable {
    public private(set) var colorSpace: ColorSpace
    public private(set) var components: [Double]

    public static let black = Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    public static let white = Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    public static let clear = Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        colorSpace = .deviceRGB
        components = [red, green, blue, alpha]
    }

    public init(gray: Double, alpha: Double = 1.0) {
        colorSpace = .deviceGray
        components = [gray, alpha]
    }

    public init(cyan: Double, magenta: Double, yellow: Double, black: Double, alpha: Double = 1.0) {
        colorSpace = .deviceCMYK
        components = [cyan, magenta, yellow, black, alpha]
    }

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

    public static var defaultValidator: Validator<Color> {
        Validator().validating(.colorIsValid)
    }
}
