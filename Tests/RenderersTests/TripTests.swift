//
//  TripTests.swift
//  PureDraw
//
//  The PureDraw `trip` torture test (PureDraw #124): one maximal scene combining the whole drawing
//  vocabulary, and a set of degenerate inputs, as the executable counterpart of the rendering spec
//  (docs/spec/rendering-model.md). Exact pixels are not portable across antialiasing and libm, so
//  this gate asserts what is portable: the reference rasterizer renders the maximal scene without
//  trapping, deterministically, and actually paints something, and no degenerate input traps. The
//  cross-renderer interaction check lives in CrossRendererConsistencyTests. Adapted from Knuth's
//  `trip` / METAFONT `trap`.
//

import Core
import Geometry
import Renderers
import Testing

struct TripTests {
    @Test func maximalSceneRendersDeterministicallyWithoutTrapping() throws {
        let scene = try maximalScene()
        let renderer = BitmapRenderer(width: 200, height: 200)
        let first = try renderer.render(scene)
        let second = try renderer.render(scene)
        #expect(first.data == second.data, "the reference rasterizer must be deterministic")
        #expect(first.width == 200 && first.height == 200)
        #expect(first.data.contains { $0 != 0 }, "the trip scene must paint something")
    }

    @Test func degenerateInputsDoNotTrap() {
        // Each valid-but-degenerate input is rendered on its own context, so a validation rejection
        // of one does not mask another. Reaching the end without a process trap is the assertion;
        // a thrown validation error is an acceptable (non-trapping) outcome.
        let gradient = Gradient(stops: [
            GradientStop(color: .black, location: 0),
            GradientStop(color: .white, location: 1),
        ])
        let cases: [(String, (inout GraphicsContext) -> Void)] = [
            ("empty path fill", { $0.setFillColor(.black)
                $0.fillPath() }),
            ("zero-size rect", { $0.setFillColor(.black)
                $0.fill(Rect(x: 4, y: 4, width: 0, height: 0)) }),
            ("degenerate ellipse", { $0.setFillColor(.black)
                $0.fillEllipse(in: Rect(x: 0, y: 0, width: 0, height: 20)) }),
            ("clip to empty then fill", {
                $0.addRect(Rect(x: 5, y: 5, width: 0, height: 0))
                $0.clip()
                $0.setFillColor(.black)
                $0.fill(Rect(x: 0, y: 0, width: 64, height: 64))
            }),
            ("zero-radius radial gradient", {
                $0.drawRadialGradient(gradient, startCenter: Point(x: 32, y: 32), startRadius: 0, endCenter: Point(x: 32, y: 32), endRadius: 0)
            }),
            ("single-point path stroke", {
                $0.setStrokeColor(.black)
                $0.setLineWidth(2)
                $0.move(to: Point(x: 10, y: 10))
                $0.strokePath()
            }),
        ]
        var completed = 0
        for (_, build) in cases {
            var context = GraphicsContext()
            build(&context)
            _ = try? BitmapRenderer(width: 64, height: 64).render(context)
            completed += 1
        }
        #expect(completed == cases.count, "no degenerate input may trap the rasterizer")
    }

    // MARK: - The maximal scene

    private func maximalScene() throws -> GraphicsContext {
        var c = GraphicsContext()

        // Transform stack with save/restore.
        c.saveGState()
        c.translate(by: 10, 8)
        c.scale(by: 1.2, 1.1)
        c.rotate(by: 0.2)
        c.setFillColor(Color(red: 0.2, green: 0.4, blue: 0.8))
        c.fill(Rect(x: 0, y: 0, width: 40, height: 40))
        c.restoreGState()

        // Even-odd fill.
        c.setFillColor(Color(red: 0.9, green: 0.3, blue: 0.1, alpha: 0.7))
        c.move(to: Point(x: 50, y: 30))
        c.addLine(to: Point(x: 90, y: 30))
        c.addLine(to: Point(x: 70, y: 70))
        c.closeSubpath()
        c.fillPath(using: .evenOdd)

        // Dashed, capped, joined stroke.
        c.setStrokeColor(.black)
        c.setLineWidth(3)
        c.setLineCap(.round)
        c.setLineJoin(.bevel)
        c.setLineDash(phase: 0, lengths: [6, 3])
        c.move(to: Point(x: 10, y: 95))
        c.addLine(to: Point(x: 60, y: 115))
        c.addLine(to: Point(x: 30, y: 150))
        c.strokePath()

        // Non-separable blend over the prior content.
        c.setBlendMode(.hue)
        c.setFillColor(Color(red: 0.1, green: 0.8, blue: 0.5, alpha: 0.6))
        c.fillEllipse(in: Rect(x: 55, y: 45, width: 50, height: 50))
        c.setBlendMode(.normal)

        // Clipped linear gradient.
        c.saveGState()
        c.addRect(Rect(x: 100, y: 10, width: 80, height: 70))
        c.clip()
        c.drawLinearGradient(
            Gradient(stops: [GradientStop(color: .black, location: 0), GradientStop(color: .white, location: 1)]),
            start: Point(x: 100, y: 10), end: Point(x: 180, y: 80)
        )
        c.restoreGState()

        // Clipped radial gradient.
        c.saveGState()
        c.addEllipse(in: Rect(x: 110, y: 95, width: 70, height: 70))
        c.clip()
        c.drawRadialGradient(
            Gradient(stops: [
                GradientStop(color: Color(red: 1, green: 0, blue: 0), location: 0),
                GradientStop(color: Color(red: 0, green: 0, blue: 1), location: 1),
            ]),
            startCenter: Point(x: 145, y: 130), startRadius: 0, endCenter: Point(x: 145, y: 130), endRadius: 35
        )
        c.restoreGState()

        // Conic gradient (raster only).
        c.drawConicGradient(
            Gradient(stops: [GradientStop(color: .white, location: 0), GradientStop(color: .black, location: 1)]),
            center: Point(x: 35, y: 165), startAngle: 0
        )

        // Image sampling.
        let image = try Image(width: 4, height: 4, alphaInfo: .last, data: checkerRGBA())
        c.draw(image, in: Rect(x: 150, y: 150, width: 40, height: 40))

        // Shadowed fill.
        c.saveGState()
        c.setShadow(offset: Point(x: 3, y: 3), blur: 2, color: Color(gray: 0, alpha: 0.5))
        c.setFillColor(Color(red: 0.5, green: 0.2, blue: 0.9))
        c.fill(Rect(x: 18, y: 55, width: 22, height: 22))
        c.restoreGState()

        // Transparency layer with group alpha.
        c.beginTransparencyLayer()
        c.setAlpha(0.5)
        c.setFillColor(.white)
        c.fill(Rect(x: 120, y: 120, width: 30, height: 30))
        c.endTransparencyLayer()

        // Text.
        c.saveGState()
        try c.setFont(Font(data: SVGTextTests.miniFontBytes))
        c.setFontSize(24)
        c.setFillColor(.black)
        c.showText("A", at: Point(x: 12, y: 188))
        c.restoreGState()

        return c
    }

    private func checkerRGBA() -> [UInt8] {
        var data: [UInt8] = []
        for index in 0 ..< 16 {
            let on = (index + index / 4) % 2 == 0
            data += on ? [220, 40, 40, 255] : [40, 40, 220, 200]
        }
        return data
    }
}
