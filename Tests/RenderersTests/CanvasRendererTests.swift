//
//  CanvasRendererTests.swift
//  PureDraw
//
//  Output-correctness tests for CanvasRenderer (PureDraw #113, audit .audit/PureDraw.md #4).
//  CanvasRenderer was only smoke-tested ("generates without error"); these validate the
//  actual emitted JavaScript: operation generation, blend-mode mapping, clip and transform
//  translation, the configurable context name, and the empty-input skeleton.
//

import Core
import Geometry
import Renderers
import Testing

struct CanvasRendererTests {
    @Test func emptyContextEmitsSaveRestoreSkeleton() throws {
        let js = try CanvasRenderer().render(GraphicsContext())
        #expect(js.contains("ctx.save();"), "skeleton must open with a save")
        #expect(js.contains("ctx.restore();"), "skeleton must close with a restore")
    }

    @Test func contextNameIsConfigurable() throws {
        var c = GraphicsContext()
        c.setFillColor(.white)
        c.fill(Rect(x: 0, y: 0, width: 10, height: 10))
        let js = try CanvasRenderer(contextName: "surface").render(c)
        #expect(js.contains("surface."), "emitted calls must use the configured context name")
        #expect(!js.contains("ctx."), "default name must not leak when overridden")
    }

    @Test func fillEmitsFillStyleAndFill() throws {
        var c = GraphicsContext()
        c.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        c.fill(Rect(x: 4, y: 6, width: 20, height: 12))
        let js = try CanvasRenderer().render(c)
        #expect(js.contains("fillStyle"), "a fill must set fillStyle")
        #expect(js.contains(".fill('nonzero');"), "a winding fill must emit fill('nonzero')")
        #expect(js.contains("255"), "the red fill color must appear in the fillStyle")
    }

    @Test func strokeEmitsStrokeStyleAndStroke() throws {
        var c = GraphicsContext()
        c.setStrokeColor(Color(red: 0, green: 0, blue: 1, alpha: 1))
        c.setLineWidth(3)
        c.move(to: Point(x: 2, y: 2))
        c.addLine(to: Point(x: 30, y: 20))
        c.strokePath()
        let js = try CanvasRenderer().render(c)
        #expect(js.contains("strokeStyle"), "a stroke must set strokeStyle")
        #expect(js.contains(".stroke();"), "a stroke must emit stroke()")
    }

    @Test func clipEmitsBeginPathAndClip() throws {
        var c = GraphicsContext()
        c.addRect(Rect(x: 5, y: 5, width: 20, height: 20))
        c.clip()
        c.setFillColor(.white)
        c.fill(Rect(x: 0, y: 0, width: 40, height: 40))
        let js = try CanvasRenderer().render(c)
        #expect(js.contains("beginPath();"), "a clip must begin a path")
        #expect(js.contains("clip();"), "a clip must emit clip()")
    }

    @Test func transformEmitsTransformMatrix() throws {
        var c = GraphicsContext()
        c.concatenate(AffineTransform(a: 2, b: 0, c: 0, d: 1, tx: 7, ty: 9))
        c.setFillColor(.white)
        c.fill(Rect(x: 0, y: 0, width: 10, height: 10))
        let js = try CanvasRenderer().render(c)
        #expect(js.contains("transform(2.0, 0.0, 0.0, 1.0, 7.0, 9.0);"), "the CTM must map to a canvas transform() with the same matrix")
    }

    @Test func blendModeMapsToCompositeOperation() throws {
        // normal is the canvas default (source-over) and is not emitted; the non-default modes
        // must map to their canvas composite-operation names.
        let cases: [(BlendMode, String)] = [(.multiply, "multiply"), (.plusLighter, "lighter"), (.plusDarker, "darker")]
        for (mode, expected) in cases {
            var c = GraphicsContext()
            c.setBlendMode(mode)
            c.setFillColor(.white)
            c.fill(Rect(x: 0, y: 0, width: 10, height: 10))
            let js = try CanvasRenderer().render(c)
            #expect(js.contains("globalCompositeOperation = '\(expected)';"), "\(mode) must map to canvas '\(expected)'")
        }
    }

    @Test func invalidContextNameThrows() throws {
        // The context name is interpolated directly into the emitted JS, so an empty name or
        // one with spaces/punctuation (which would produce broken or injectable output) must
        // be rejected at render time rather than emitted silently (#115).
        for bad in ["", " ", "ctx ", "my ctx", "1ctx", "ctx;evil()", "a-b", "ctx.x", "(", "\n"] {
            #expect(throws: (any Error).self, "invalid contextName \(bad.debugDescription) must throw") {
                _ = try CanvasRenderer(contextName: bad).render(GraphicsContext())
            }
        }
        // Valid identifiers must render without throwing.
        for good in ["ctx", "_ctx", "$c", "context2D", "myCanvas_1"] {
            #expect(throws: Never.self, "valid contextName \(good) must not throw") {
                _ = try CanvasRenderer(contextName: good).render(GraphicsContext())
            }
        }
    }

    @Test func alphaEmitsGlobalAlpha() throws {
        var c = GraphicsContext()
        c.setAlpha(0.5)
        c.setFillColor(.white)
        c.fill(Rect(x: 0, y: 0, width: 10, height: 10))
        let js = try CanvasRenderer().render(c)
        #expect(js.contains("globalAlpha = 0.5;"), "setAlpha must map to globalAlpha")
    }
}
