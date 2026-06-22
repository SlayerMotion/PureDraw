//
//  SRGBTransfer.swift
//  PureDraw
//

import Foundation

/// The sRGB transfer function (IEC 61966-2-1): the exact, standardized mapping between a linear-light
/// component and its sRGB-encoded (gamma) value. It is a small linear segment near zero joined to a
/// `2.4` power curve, chosen so the two meet with a continuous value and slope.
///
/// This is the basis of colour management for the common matrix-RGB spaces: blending and gradient
/// interpolation are physically correct in linear light, and display values are sRGB-encoded. The
/// formulas are the standard's, not an approximation. Components at or below the small-signal threshold
/// (which includes negative, out-of-gamut values) take the linear segment, so no fractional power of a
/// negative base is evaluated.
public enum SRGBTransfer {
    /// Encodes a linear-light component to its sRGB (gamma) value.
    public static func encode(_ linear: Double) -> Double {
        linear <= 0.003_130_8 ? 12.92 * linear : 1.055 * pow(linear, 1.0 / 2.4) - 0.055
    }

    /// Decodes an sRGB-encoded component to linear light.
    public static func decode(_ encoded: Double) -> Double {
        encoded <= 0.040_45 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }
}

public extension Color {
    /// This colour with its RGB components decoded from sRGB to linear light; alpha is unchanged.
    /// Interpolating or blending in the returned linear space is physically correct.
    func linearized() -> Color {
        Color(
            red: SRGBTransfer.decode(red),
            green: SRGBTransfer.decode(green),
            blue: SRGBTransfer.decode(blue),
            alpha: alpha
        )
    }

    /// This colour with its linear-light RGB components encoded to sRGB; alpha is unchanged. The
    /// inverse of ``linearized()``.
    func sRGBEncoded() -> Color {
        Color(
            red: SRGBTransfer.encode(red),
            green: SRGBTransfer.encode(green),
            blue: SRGBTransfer.encode(blue),
            alpha: alpha
        )
    }
}
