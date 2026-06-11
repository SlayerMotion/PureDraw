//
//  ShadowRasterizer.swift
//  PureDraw
//

import Core
import Geometry

/// The shared software shadow kernel: blurs and offsets an alpha plane the same
/// way for every renderer, so a transparency-layer shadow and an explicit
/// `dropShadow` produce the same silhouette, and so `BitmapRenderer` and
/// `CoreGraphicsRenderer` stay consistent.
///
/// The box blur approximates CoreGraphics's Gaussian shadow: structurally
/// equivalent, not pixel-identical.
enum ShadowRasterizer {
    /// The blurred, offset shadow alpha plane (device space) for a source alpha
    /// plane. `width`/`height` are the canvas size; `blur` is clamped so an
    /// adversarial radius cannot run an unbounded loop.
    static func shadowAlpha(
        coverage: [Double],
        width: Int,
        height: Int,
        offset: Point,
        blur: Double
    ) -> [Double] {
        let radius = min(Int(blur.rounded()), max(width, height))
        let blurred = boxBlurredAlpha(coverage, width: width, height: height, radius: radius)
        let dx = Int(offset.x.rounded())
        let dy = Int(offset.y.rounded())
        var result = [Double](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let sx = x - dx
                let sy = y - dy
                guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                result[y * width + x] = blurred[sy * width + sx]
            }
        }
        return result
    }

    /// A separable box blur of an alpha plane, clamping at the edges. The identity
    /// when `radius <= 0`.
    static func boxBlurredAlpha(_ source: [Double], width: Int, height: Int, radius: Int) -> [Double] {
        guard radius > 0 else { return source }
        let window = Double(radius * 2 + 1)
        var horizontal = [Double](repeating: 0, count: source.count)
        for y in 0 ..< height {
            for x in 0 ..< width {
                var sum = 0.0
                for k in -radius ... radius {
                    let xx = min(width - 1, max(0, x + k))
                    sum += source[y * width + xx]
                }
                horizontal[y * width + x] = sum / window
            }
        }
        var blurred = [Double](repeating: 0, count: source.count)
        for x in 0 ..< width {
            for y in 0 ..< height {
                var sum = 0.0
                for k in -radius ... radius {
                    let yy = min(height - 1, max(0, y + k))
                    sum += horizontal[yy * width + x]
                }
                blurred[y * width + x] = sum / window
            }
        }
        return blurred
    }
}
