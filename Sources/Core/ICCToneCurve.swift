//
//  ICCToneCurve.swift
//  PureDraw
//

import Foundation

/// A per-channel tone reproduction curve (TRC) from an ICC profile: the function that maps a device
/// value to (or from) linear light. ICC stores these as `curveType` (`curv`, a gamma value or a sampled
/// lookup table) or `parametricCurveType` (`para`, one of five closed-form functions). This models all
/// of them and evaluates the curve, so a parsed profile's encoding can be applied uniformly.
public enum ICCToneCurve: Equatable, Sendable {
    /// An identity curve (a `curv` tag with zero entries).
    case identity
    /// A pure gamma curve `Y = X^gamma` (a `curv` tag with one entry).
    case gamma(Double)
    /// A sampled curve (a `curv` tag with many entries), interpolated linearly. Values are in `0...1`.
    case table([Double])
    /// A parametric curve (a `para` tag): `functionType` selects one of the ICC closed forms, evaluated
    /// from `parameters` `[g, a, b, c, d, e, f]` (only the leading ones the type uses are present).
    case parametric(functionType: Int, parameters: [Double])

    /// Evaluates the curve at `x` in `0...1`. The ICC parametric forms (ICC.1 §10.18) join a power curve
    /// to a linear segment; below the small-signal break each uses its linear part, so no fractional
    /// power of a negative base is evaluated.
    public func value(at x: Double) -> Double {
        switch self {
        case .identity:
            return x
        case let .gamma(g):
            return x <= 0 ? 0 : pow(x, g)
        case let .table(values):
            guard values.count > 1 else { return values.first ?? x }
            let clamped = min(1, max(0, x))
            let position = clamped * Double(values.count - 1)
            let lower = Int(position)
            if lower >= values.count - 1 { return values[values.count - 1] }
            let fraction = position - Double(lower)
            return values[lower] + (values[lower + 1] - values[lower]) * fraction
        case let .parametric(functionType, p):
            return Self.parametric(functionType, p, x)
        }
    }

    private static func power(_ base: Double, _ exponent: Double) -> Double {
        base <= 0 ? 0 : pow(base, exponent)
    }

    private static func parametric(_ type: Int, _ p: [Double], _ x: Double) -> Double {
        func at(_ index: Int) -> Double {
            index < p.count ? p[index] : 0
        }
        let g = at(0), a = at(1), b = at(2), c = at(3), d = at(4), e = at(5), f = at(6)
        switch type {
        case 0:
            return power(x, g)
        case 1:
            return x >= -b / a ? power(a * x + b, g) : 0
        case 2:
            return x >= -b / a ? power(a * x + b, g) + c : c
        case 3:
            return x >= d ? power(a * x + b, g) : c * x
        case 4:
            return x >= d ? power(a * x + b, g) + c : e * x + f
        default:
            return x
        }
    }
}
