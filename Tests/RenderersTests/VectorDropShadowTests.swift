//
//  VectorDropShadowTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// The explicit drop shadow (`drawShadow(of:)`, the CALayer.shadowPath analog) now exports through the
/// SVG and Canvas back ends, which can express a soft offset shadow. These assert the emitted markup
/// carries the spec-correct shadow construct, that the offset, blur, and colour are threaded through,
/// and that with no shadow set nothing is emitted. The remaining vector back ends (PDF, PostScript)
/// cannot express a Gaussian blur and keep a documented `UnsupportedOperationError`.
struct VectorDropShadowTests {
    private func shadowedContext() -> GraphicsContext {
        var context = GraphicsContext()
        context.setShadow(offset: Point(x: 4, y: 6), blur: 8, color: Color(red: 0, green: 0, blue: 0, alpha: 0.5))
        context.drawShadow(of: Path(rect: Rect(x: 10, y: 10, width: 30, height: 20)))
        return context
    }

    @Test func svgEmitsAShadowOnlyFilter() throws {
        let svg = try SVGRenderer(width: 64, height: 64).draw(shadowedContext())
        // A shadow-only filter: blur the source alpha, offset it, flood with the colour, composite in.
        #expect(svg.contains("<filter id=\"dropshadow-"))
        #expect(svg.contains("feGaussianBlur"))
        #expect(svg.contains("in=\"SourceAlpha\""))
        #expect(svg.contains("dx=\"4.0\""))
        #expect(svg.contains("dy=\"6.0\""))
        #expect(svg.contains("stdDeviation=\"4.0\"")) // blur 8 -> stdDeviation 4
        #expect(svg.contains("flood-opacity=\"0.5\""))
        #expect(svg.contains("filter=\"url(#dropshadow-"))
        // It must NOT reuse the source-plus-shadow feDropShadow used for an implicit state shadow.
        #expect(!svg.contains("feDropShadow"))
    }

    @Test func canvasEmitsBlurAndOffsetFill() throws {
        let js = try CanvasRenderer().draw(shadowedContext())
        #expect(js.contains("filter = 'blur(4.0px)'")) // blur 8 -> 4px Gaussian
        #expect(js.contains("translate(4.0, 6.0)"))
        #expect(js.contains("shadowColor = 'transparent'")) // inherited state shadow cancelled
        #expect(js.contains("filter = 'none'")) // reset afterwards
    }

    @Test func noShadowSetEmitsNothing() throws {
        var context = GraphicsContext()
        // No setShadow: the drop shadow paints nothing, matching the raster renderer.
        context.drawShadow(of: Path(rect: Rect(x: 0, y: 0, width: 10, height: 10)))
        let svg = try SVGRenderer(width: 16, height: 16).draw(context)
        let js = try CanvasRenderer().draw(context)
        #expect(!svg.contains("dropshadow-"))
        #expect(!js.contains("blur("))
    }
}
