//
//  SeparableBlendModeTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// The software `BitmapRenderer` must composite the W3C separable blend modes and the
/// additive plus modes, matching the native `CGBlendMode` the `CoreGraphicsRenderer` uses.
/// Backdrops are kept opaque so the result alpha is 1 and the premultiplied buffer reads
/// back as the straight colour, making the expected values exact.
struct SeparableBlendModeTests {
    /// Paints an opaque `backdrop`, then `source` on top in `mode`, and returns the overlap
    /// pixel as 0...255 RGB.
    private func overlap(_ mode: BlendMode, backdrop: Color, source: Color) throws -> (r: Int, g: Int, b: Int) {
        var context = GraphicsContext()
        context.setFillColor(backdrop)
        context.addRect(Rect(x: 0, y: 0, width: 4, height: 4))
        context.fillPath()
        context.setBlendMode(mode)
        context.setFillColor(source)
        context.addRect(Rect(x: 0, y: 0, width: 4, height: 4))
        context.fillPath()
        let data = try BitmapRenderer(width: 4, height: 4).render(context).data
        let i = (2 * 4 + 2) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    private func near(_ a: Int, _ b: Int, _ tol: Int = 2) -> Bool {
        abs(a - b) <= tol
    }

    private let backdrop = Color(red: 0.4, green: 0.6, blue: 0.8, alpha: 1)
    private let source = Color(red: 0.5, green: 0.25, blue: 0.0, alpha: 1)

    @Test func screenLightens() throws {
        // screen = s + d - s·d, per channel: (0.7, 0.7, 0.8).
        let c = try overlap(.screen, backdrop: backdrop, source: source)
        #expect(near(c.r, 179) && near(c.g, 179) && near(c.b, 204))
    }

    @Test func plusLighterAddsAndClamps() throws {
        // plus-lighter = min(1, s + d): (0.9, 0.85, 0.8).
        let c = try overlap(.plusLighter, backdrop: backdrop, source: source)
        #expect(near(c.r, 230) && near(c.g, 217) && near(c.b, 204))
    }

    @Test func darkenAndLightenPickPerChannel() throws {
        let dark = try overlap(.darken, backdrop: backdrop, source: source) // (min): (0.4, 0.25, 0.0)
        #expect(near(dark.r, 102) && near(dark.g, 64) && near(dark.b, 0))
        let light = try overlap(.lighten, backdrop: backdrop, source: source) // (max): (0.5, 0.6, 0.8)
        #expect(near(light.r, 128) && near(light.g, 153) && near(light.b, 204))
    }

    @Test func differenceAndExclusion() throws {
        let diff = try overlap(.difference, backdrop: backdrop, source: source) // |s-d|: (0.1, 0.35, 0.8)
        #expect(near(diff.r, 26) && near(diff.g, 89) && near(diff.b, 204))
        let excl = try overlap(.exclusion, backdrop: backdrop, source: source) // s+d-2sd: (0.5, 0.55, 0.8)
        #expect(near(excl.r, 128) && near(excl.g, 140) && near(excl.b, 204))
    }

    @Test func multiplyUnchanged() throws {
        // Regression: the pre-existing multiply case keeps its exact output. s·d: (0.2, 0.15, 0.0).
        let c = try overlap(.multiply, backdrop: backdrop, source: source)
        #expect(near(c.r, 51) && near(c.g, 38) && near(c.b, 0))
    }

    @Test func plusLighterCompositesTranslucentSourcePremultiplied() throws {
        // The emitter's case: a half-transparent red spark added over a blue backdrop. The
        // premultiplied red (1·0.5) adds to the backdrop blue: (0.5, 0, 0.5), alpha 1.
        let c = try overlap(
            .plusLighter,
            backdrop: Color(red: 0, green: 0, blue: 0.5, alpha: 1),
            source: Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        )
        #expect(near(c.r, 128) && near(c.g, 0) && near(c.b, 128))
    }
}
