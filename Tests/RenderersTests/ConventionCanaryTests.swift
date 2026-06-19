//
//  ConventionCanaryTests.swift
//  PureDraw
//
//  External-conformance canaries for SHARED SEMANTIC CONVENTIONS. Parity (one backend ==
//  another) and even first-principles pixel checks can all agree on the WRONG convention if
//  the spec, oracle, and implementation share the same assumption. These tests do not
//  consult the engine's own algebra or constants: each asserts a value derived by hand from
//  the standard the engine commits to (Core Animation / Quartz: non-linear device-RGB
//  compositing, nonzero/even-odd fill rules). A convention drift changes the answer by a
//  large, unambiguous margin and trips the canary where a tolerance-based test would not.
//

@testable import Core
import Geometry
@testable import Renderers
import Testing

struct ConventionCanaryTests {
    @Test func sourceOverCompositesInSRGBNotLinearLight() throws {
        // Opaque blue, then red at alpha 0.5 over it. Straight-alpha source-over in sRGB
        // device RGB: out = src*a + dst*(1 - a) on the 0...1 sRGB channels (NO gamma
        // round-trip): red = 0.5, green = 0, blue = 0.5, alpha = 1. Linear-light compositing
        // would give sRGB(0.5_linear) ~= 0.735 per channel instead.
        var context = GraphicsContext()
        let frame = Rect(x: 0, y: 0, width: 8, height: 8)
        context.setFillColor(Color(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(frame)
        context.setAlpha(0.5)
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(frame)

        let pixel = try BitmapRenderer(width: 8, height: 8).draw(context).pixelColor(x: 4, y: 4)
        // 0.5 target vs the 0.735 linear alternative differ by ~0.23, so 0.02 is a real
        // canary (catches a colour-space drift), not just rounding slack.
        #expect(abs(pixel.red - 0.5) < 0.02, "source-over red should be 0.5 in sRGB; got \(pixel.red) (~0.735 would mean linear-light blending)")
        #expect(pixel.green < 0.02, "no green; got \(pixel.green)")
        #expect(abs(pixel.blue - 0.5) < 0.02, "source-over blue should be 0.5 in sRGB; got \(pixel.blue)")
        #expect(pixel.alpha > 0.98, "opaque over opaque stays opaque; got \(pixel.alpha)")
    }

    @Test func fillRuleNonzeroFillsWhatEvenOddHollows() throws {
        // A self-intersecting path: an outer 8x8 box and an inner 4x4 box wound the SAME
        // direction. The classic fill-rule discriminator, independent of the engine:
        //   nonzero: the inner region has winding 2 (both loops same sign) -> FILLED.
        //   even-odd: a ray from the inner region crosses 2 edges (even) -> HOLE.
        // So the centre is opaque under .winding and empty under .evenOdd. Swapping which
        // FillRule case denotes which rule (a shared convention error) trips this.
        func centre(_ rule: FillRule) throws -> Color {
            var context = GraphicsContext()
            var path = Path()
            path.move(to: Point(x: 0, y: 0))
            path.addLine(to: Point(x: 8, y: 0))
            path.addLine(to: Point(x: 8, y: 8))
            path.addLine(to: Point(x: 0, y: 8))
            path.closeSubpath()
            path.move(to: Point(x: 2, y: 2))
            path.addLine(to: Point(x: 6, y: 2))
            path.addLine(to: Point(x: 6, y: 6))
            path.addLine(to: Point(x: 2, y: 6))
            path.closeSubpath()
            context.setFillColor(Color(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(path, using: rule)
            return try BitmapRenderer(width: 8, height: 8).draw(context).pixelColor(x: 4, y: 4)
        }
        let winding = try centre(.winding)
        let evenOdd = try centre(.evenOdd)
        #expect(winding.blue > 0.9 && winding.alpha > 0.9, "nonzero winding fills the inner region; got \(winding)")
        #expect(evenOdd.alpha < 0.1, "even-odd leaves the inner region a hole; got alpha \(evenOdd.alpha)")
    }
}
