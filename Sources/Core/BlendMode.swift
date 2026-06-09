//
//  BlendMode.swift
//  PureDraw
//

/// Blend modes and compositing operations for compositing shapes in the graphics context.
public enum BlendMode: String, Sendable, CaseIterable {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge = "color-dodge"
    case colorBurn = "color-burn"
    case softLight = "soft-light"
    case hardLight = "hard-light"
    case difference
    case exclusion

    // Non-separable blend modes
    case hue
    case saturation
    case color
    case luminosity

    // Porter-Duff compositing operators
    case clear
    case copy
    case sourceIn = "source-in"
    case sourceOut = "source-out"
    case sourceAtop = "source-atop"
    case destinationOver = "destination-over"
    case destinationIn = "destination-in"
    case destinationOut = "destination-out"
    case destinationAtop = "destination-atop"
    case xor
    case plusDarker = "plus-darker"
    case plusLighter = "plus-lighter"

    /// Returns true if this blend mode is supported by CSS `mix-blend-mode`.
    public var isCSSBlendMode: Bool {
        switch self {
        case .normal, .multiply, .screen, .overlay, .darken, .lighten,
             .colorDodge, .colorBurn, .softLight, .hardLight, .difference, .exclusion,
             .hue, .saturation, .color, .luminosity:
            true
        default:
            false
        }
    }
}
