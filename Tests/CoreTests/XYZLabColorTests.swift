//
//  XYZLabColorTests.swift
//  PureDraw
//

@testable import Core
import Testing

/// Device-independent colour: sRGB to CIE XYZ (D65 primaries matrix) to CIE L*a*b*. These check the
/// fixed points (black and white), the documented Lab of sRGB primaries, and the colour-difference
/// metric, all against the standard's values.
struct XYZLabColorTests {
    private func approx(_ a: Double, _ b: Double, tol: Double) -> Bool {
        abs(a - b) <= tol
    }

    @Test func whiteMapsToD65AndLab100() {
        let xyz = Color(red: 1, green: 1, blue: 1, alpha: 1).xyz()
        // sRGB white is the D65 white point.
        #expect(approx(xyz.x, 0.95047, tol: 1e-3))
        #expect(approx(xyz.y, 1.0, tol: 1e-3))
        #expect(approx(xyz.z, 1.08883, tol: 1e-3))
        let lab = Color(red: 1, green: 1, blue: 1, alpha: 1).lab()
        #expect(approx(lab.l, 100, tol: 1e-3))
        #expect(approx(lab.a, 0, tol: 1e-3))
        #expect(approx(lab.b, 0, tol: 1e-3))
    }

    @Test func blackMapsToZero() {
        let lab = Color(red: 0, green: 0, blue: 0, alpha: 1).lab()
        #expect(approx(lab.l, 0, tol: 1e-9))
        #expect(approx(lab.a, 0, tol: 1e-9))
        #expect(approx(lab.b, 0, tol: 1e-9))
    }

    @Test func sRGBRedHasTheDocumentedLab() {
        // The standard L*a*b* of pure sRGB red.
        let lab = Color(red: 1, green: 0, blue: 0, alpha: 1).lab()
        #expect(approx(lab.l, 53.2408, tol: 0.01))
        #expect(approx(lab.a, 80.0925, tol: 0.01))
        #expect(approx(lab.b, 67.2032, tol: 0.01))
    }

    @Test func midGrayLightness() {
        // sRGB 50% gray is far from L* 50: it is about 53.39 (luminance, not code value, drives L*).
        let lab = Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1).lab()
        #expect(approx(lab.l, 53.389, tol: 0.01))
        // Near-neutral: the standard 7-digit matrix is not perfectly grey-balanced, so a/b sit at ~1e-5.
        #expect(approx(lab.a, 0, tol: 1e-3))
        #expect(approx(lab.b, 0, tol: 1e-3))
    }

    @Test func deltaEIsZeroForEqualColorsAndLargeForOpposites() {
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1).lab()
        #expect(red.deltaE76(to: red) == 0)
        let black = Color(red: 0, green: 0, blue: 0, alpha: 1).lab()
        let white = Color(red: 1, green: 1, blue: 1, alpha: 1).lab()
        // Black-to-white is a full lightness sweep: ΔE = 100.
        #expect(approx(black.deltaE76(to: white), 100, tol: 1e-3))
    }
}
