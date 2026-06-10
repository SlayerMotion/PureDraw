//
//  Image+Sampling.swift
//  PureDraw
//

public extension Image {
    /// Samples the image at normalized coordinates `(u, v)` in `0...1`,
    /// honoring the interpolation quality: `.none` snaps to the nearest
    /// pixel; every other quality blends the four neighboring pixels
    /// bilinearly in premultiplied space.
    func sampledColor(u: Double, v: Double, quality: InterpolationQuality) -> Color {
        guard quality != .none else {
            return nearestColor(u: u, v: v)
        }

        let sampleX = u * Double(width) - 0.5
        let sampleY = v * Double(height) - 0.5
        let x0 = Int(sampleX.rounded(.down))
        let y0 = Int(sampleY.rounded(.down))
        let fractionX = sampleX - Double(x0)
        let fractionY = sampleY - Double(y0)

        let clampedX0 = min(width - 1, max(0, x0))
        let clampedX1 = min(width - 1, max(0, x0 + 1))
        let clampedY0 = min(height - 1, max(0, y0))
        let clampedY1 = min(height - 1, max(0, y0 + 1))

        let c00 = premultiplied(pixelColor(x: clampedX0, y: clampedY0))
        let c10 = premultiplied(pixelColor(x: clampedX1, y: clampedY0))
        let c01 = premultiplied(pixelColor(x: clampedX0, y: clampedY1))
        let c11 = premultiplied(pixelColor(x: clampedX1, y: clampedY1))

        let red = bilerp(c00.red, c10.red, c01.red, c11.red, fractionX: fractionX, fractionY: fractionY)
        let green = bilerp(c00.green, c10.green, c01.green, c11.green, fractionX: fractionX, fractionY: fractionY)
        let blue = bilerp(c00.blue, c10.blue, c01.blue, c11.blue, fractionX: fractionX, fractionY: fractionY)
        let alpha = bilerp(c00.alpha, c10.alpha, c01.alpha, c11.alpha, fractionX: fractionX, fractionY: fractionY)

        guard alpha > 0 else { return .clear }
        return Color(red: red / alpha, green: green / alpha, blue: blue / alpha, alpha: alpha)
    }

    private func nearestColor(u: Double, v: Double) -> Color {
        let x = min(width - 1, max(0, Int(u * Double(width))))
        let y = min(height - 1, max(0, Int(v * Double(height))))
        return pixelColor(x: x, y: y)
    }

    private func premultiplied(_ color: Color) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        (color.red * color.alpha, color.green * color.alpha, color.blue * color.alpha, color.alpha)
    }

    private func bilerp(_ v00: Double, _ v10: Double, _ v01: Double, _ v11: Double, fractionX: Double, fractionY: Double) -> Double {
        let top = v00 + (v10 - v00) * fractionX
        let bottom = v01 + (v11 - v01) * fractionX
        return top + (bottom - top) * fractionY
    }
}
