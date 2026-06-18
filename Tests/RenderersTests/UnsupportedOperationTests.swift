//
//  UnsupportedOperationTests.swift
//  PureDraw
//
//  The vector renderers (SVG, PostScript, Canvas, PDF) cannot represent an explicit
//  drop-shadow or a projective image warp, and previously skipped them silently, losing part
//  of the drawing with no signal (PureDraw #114, audit .audit/PureDraw.md #5). They now throw
//  a typed UnsupportedOperationError instead. Operations they CAN represent (or that are
//  expanded/lowered upstream: layers, text) still render.
//

import Core
import Geometry
import Renderers
import Testing

struct UnsupportedOperationTests {
    private func dropShadowContext() -> GraphicsContext {
        var c = GraphicsContext()
        c.setFillColor(.white)
        c.setShadow(offset: Point(x: 2, y: 2), blur: 3, color: .black)
        c.drawShadow(of: Path(rect: Rect(x: 10, y: 10, width: 20, height: 20)))
        return c
    }

    private func projectiveContext() throws -> GraphicsContext {
        var c = GraphicsContext()
        let image = try Image(width: 2, height: 2, alphaInfo: .last, data: [UInt8](repeating: 200, count: 16))
        c.draw(image, in: Rect(x: 0, y: 0, width: 20, height: 20), mappingTo: .identity)
        return c
    }

    private func plainContext() -> GraphicsContext {
        var c = GraphicsContext()
        c.setFillColor(.white)
        c.fill(Rect(x: 5, y: 5, width: 20, height: 20))
        return c
    }

    @Test func vectorRenderersThrowOnDropShadow() throws {
        let c = dropShadowContext()
        #expect(throws: UnsupportedOperationError.self) { _ = try SVGRenderer().render(c) }
        #expect(throws: UnsupportedOperationError.self) { _ = try PostScriptRenderer().render(c) }
        #expect(throws: UnsupportedOperationError.self) { _ = try CanvasRenderer().render(c) }
        #expect(throws: UnsupportedOperationError.self) { _ = try PDFRenderer(width: 40, height: 40).render(c) }
    }

    @Test func vectorRenderersThrowOnProjectiveImage() throws {
        let c = try projectiveContext()
        #expect(throws: UnsupportedOperationError.self) { _ = try SVGRenderer().render(c) }
        #expect(throws: UnsupportedOperationError.self) { _ = try PostScriptRenderer().render(c) }
        #expect(throws: UnsupportedOperationError.self) { _ = try CanvasRenderer().render(c) }
        #expect(throws: UnsupportedOperationError.self) { _ = try PDFRenderer(width: 40, height: 40).render(c) }
    }

    @Test func errorNamesOperationAndRenderer() {
        let c = dropShadowContext()
        do {
            _ = try SVGRenderer().render(c)
            Issue.record("expected SVGRenderer to throw on dropShadow")
        } catch let error as UnsupportedOperationError {
            #expect(error.operation == "dropShadow")
            #expect(error.renderer == "SVGRenderer")
        } catch {
            Issue.record("expected UnsupportedOperationError, got \(error)")
        }
    }

    @Test func supportedContentStillRenders() throws {
        let c = plainContext()
        _ = try SVGRenderer().render(c)
        _ = try PostScriptRenderer().render(c)
        _ = try CanvasRenderer().render(c)
        _ = try PDFRenderer(width: 40, height: 40).render(c)
    }
}
