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
/// The blur is a three-pass box-blur approximation of a Gaussian, matching Core Animation's shadow:
/// `CALayer.shadowRadius` is the Gaussian standard deviation (verified against `CALayer.render(in:)` --
/// a blurred step edge transitions over ~2 * radius, i.e. sigma == radius), so a single box blur (which
/// leaves the silhouette core opaque) is not faithful. Three successive box blurs converge to a Gaussian
/// by the central limit theorem; the box sizes are chosen to match the target variance (Kuckir's method).
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
        // A non-finite blur or offset (e.g. a malformed shadow or an out-of-range animated
        // value) traps the `Int(...)` conversions; treat it as no blur / no offset.
        let sigma = min(blur.isFinite ? blur : 0, Double(max(width, height)))
        let blurred = gaussianBlurredAlpha(coverage, width: width, height: height, sigma: sigma)
        let dx = Int((offset.x.isFinite ? offset.x : 0).rounded())
        let dy = Int((offset.y.isFinite ? offset.y : 0).rounded())
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

    /// A Gaussian blur of an alpha plane with standard deviation `sigma`, approximated by three
    /// successive box blurs (the identity when `sigma <= 0`). Three boxes converge to a Gaussian; their
    /// integer half-widths are chosen so the combined variance matches `sigma`, following Kuckir's
    /// "Fast Gaussian Blur" box sizing. This reproduces Core Animation's softened, spread shadow where a
    /// single box blur would leave the silhouette core fully opaque.
    static func gaussianBlurredAlpha(_ source: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
        guard sigma > 0 else { return source }
        var plane = source
        for radius in boxRadii(forGaussianSigma: sigma, passes: 3) where radius > 0 {
            plane = boxBlurredAlpha(plane, width: width, height: height, radius: radius)
        }
        return plane
    }

    /// The half-widths of `passes` box blurs whose combined variance approximates a Gaussian of standard
    /// deviation `sigma`. Each box has an odd full width (`2 * radius + 1`); some passes use the smaller
    /// width and the rest the next odd width up, so the total variance lands as close to `sigma^2` as
    /// integer boxes allow (Kuckir's method).
    static func boxRadii(forGaussianSigma sigma: Double, passes n: Int) -> [Int] {
        guard sigma > 0, n > 0 else { return [] }
        // Ideal (real-valued) odd box width for `n` passes matching the target variance.
        let wIdeal = (12 * sigma * sigma / Double(n) + 1).squareRoot()
        var wl = Int(wIdeal.rounded(.down))
        if wl % 2 == 0 { wl -= 1 } // box widths must be odd (a symmetric integer half-width)
        wl = max(wl, 1)
        let wu = wl + 2
        // How many of the `n` passes use the smaller width `wl` (the rest use `wu`).
        let mIdeal = (12 * sigma * sigma - Double(n * wl * wl) - Double(4 * n * wl) - Double(3 * n))
            / Double(-4 * wl - 4)
        let m = max(0, min(n, Int(mIdeal.rounded())))
        return (0 ..< n).map { i in ((i < m ? wl : wu) - 1) / 2 }
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
