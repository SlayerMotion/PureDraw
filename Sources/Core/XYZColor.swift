//
//  XYZColor.swift
//  PureDraw
//

import Foundation

/// A colour in the CIE 1931 XYZ space, the device-independent space at the centre of colour management
/// (it is the profile connection space ICC profiles convert through). `X`, `Y`, `Z` are tristimulus
/// values with `Y` the luminance; here they are relative to the D65 white point, the sRGB reference
/// white.
public struct XYZColor: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    /// Creates an XYZ colour from its tristimulus values.
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Converts a *linear-light* sRGB colour to XYZ using the standard sRGB primaries matrix (D65). The
    /// input must already be linearized (see ``Color/linearized()``); applying this to gamma-encoded
    /// values would be wrong.
    public init(linearRed r: Double, green g: Double, blue b: Double) {
        x = 0.412_456_4 * r + 0.357_576_1 * g + 0.180_437_5 * b
        y = 0.212_672_9 * r + 0.715_152_2 * g + 0.072_175_0 * b
        z = 0.019_333_9 * r + 0.119_192_0 * g + 0.950_304_1 * b
    }

    /// The matching CIE L*a*b* colour, computed against the D65 white point with the exact CIE
    /// piecewise function (the cube root above the small-signal threshold `216/24389`, linear below).
    public var lab: LabColor {
        let whiteX = 0.950_47, whiteY = 1.0, whiteZ = 1.088_83
        let fx = Self.labF(x / whiteX)
        let fy = Self.labF(y / whiteY)
        let fz = Self.labF(z / whiteZ)
        return LabColor(l: 116.0 * fy - 16.0, a: 500.0 * (fx - fy), b: 200.0 * (fy - fz))
    }

    private static func labF(_ t: Double) -> Double {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        return t > epsilon ? Foundation.cbrt(t) : (kappa * t + 16.0) / 116.0
    }
}

public extension Color {
    /// This sRGB colour as device-independent CIE XYZ: linearize, then apply the sRGB primaries matrix.
    func xyz() -> XYZColor {
        let linear = linearized()
        return XYZColor(linearRed: linear.red, green: linear.green, blue: linear.blue)
    }

    /// This sRGB colour as CIE L*a*b*, for perceptual comparison.
    func lab() -> LabColor {
        xyz().lab
    }
}
