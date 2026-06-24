//
//  ShadowGaussianBlurTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// `ShadowRasterizer` approximates Core Animation's Gaussian shadow blur (three box blurs, with
/// `CALayer.shadowRadius` as the Gaussian standard deviation). The defining property versus the old
/// single box blur is that the blur softens the silhouette CORE, not just its edge: a 16pt square blurred
/// at radius 6 drops its centre alpha well below opaque, and softens further as the radius grows. The
/// reference peaks come from `CALayer.render(in:)` (peak ~1.0/0.97/0.72/0.50/0.36 at radius 2/4/6/8/10 for
/// a 16pt silhouette); PureDraw's three-box approximation lands within a few percent.
@Suite("Shadow Gaussian blur")
struct ShadowGaussianBlurTests {
    private let canvas = 80

    /// Centre alpha of a 16x16 opaque square (placed at [32,48]) after a Gaussian blur of `sigma`.
    private func centrePeak(sigma: Double) -> Double {
        var src = [Double](repeating: 0, count: canvas * canvas)
        for y in 32 ..< 48 {
            for x in 32 ..< 48 {
                src[y * canvas + x] = 1.0
            }
        }
        let out = ShadowRasterizer.gaussianBlurredAlpha(src, width: canvas, height: canvas, sigma: sigma)
        return out[40 * canvas + 40]
    }

    @Test func blurSoftensTheCoreNotJustTheEdge() {
        // A single box blur of radius 6 would leave the 16pt core fully opaque (peak 1.0). The Gaussian
        // approximation softens it well below opaque, matching Core Animation (~0.72).
        let peak = centrePeak(sigma: 6)
        #expect(peak < 0.85, "radius-6 blur should soften the core, got \(peak)")
        #expect(peak > 0.55, "radius-6 blur should not over-soften, got \(peak)")
    }

    @Test func largerRadiusSoftensMonotonically() throws {
        // Peak alpha decreases as the blur radius grows (Gaussian spreading), matching CA's
        // 1.0 -> 0.72 -> 0.50 -> 0.36 progression.
        let peaks = [2.0, 4.0, 6.0, 8.0, 10.0].map { centrePeak(sigma: $0) }
        for (a, b) in zip(peaks, peaks.dropFirst()) {
            #expect(b <= a + 1e-9, "peak should not increase with radius: \(peaks)")
        }
        let widest = try #require(peaks.first)
        let narrowest = try #require(peaks.last)
        #expect(widest > narrowest + 0.3, "blur should span a wide softening range: \(peaks)")
    }

    @Test func zeroSigmaIsIdentity() {
        var src = [Double](repeating: 0, count: canvas * canvas)
        src[40 * canvas + 40] = 1.0
        let out = ShadowRasterizer.gaussianBlurredAlpha(src, width: canvas, height: canvas, sigma: 0)
        #expect(out == src, "zero sigma must be the identity")
    }

    @Test func boxRadiiMatchTargetVariance() {
        // Three box blurs whose combined variance approximates the Gaussian: for sigma 6 the half-widths
        // are [5, 5, 6] (odd widths 11/11/13), giving an effective sigma ~5.83.
        #expect(ShadowRasterizer.boxRadii(forGaussianSigma: 6, passes: 3) == [5, 5, 6])
        let radii = ShadowRasterizer.boxRadii(forGaussianSigma: 8, passes: 3)
        let variance = radii.map { Double((2 * $0 + 1) * (2 * $0 + 1) - 1) / 12.0 }.reduce(0, +)
        #expect(abs(variance.squareRoot() - 8) < 0.5, "effective sigma should approximate the target: \(radii)")
    }
}
