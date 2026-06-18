//
//  PostScriptRendererTests.swift
//  PureDraw
//
//  Output-correctness tests for PostScriptRenderer (PureDraw #113, audit .audit/PureDraw.md
//  #4). PostScriptRenderer was only smoke-tested; these validate the emitted PostScript:
//  the EPS header and bounding box, fill / stroke / clip operator generation, path operators,
//  the even-odd vs nonzero fill distinction, and the empty-input skeleton.
//

import Core
import Geometry
import Renderers
import Testing

struct PostScriptRendererTests {
    @Test func emitsEPSHeaderAndBoundingBox() throws {
        let ps = try PostScriptRenderer().render(GraphicsContext())
        #expect(ps.hasPrefix("%!PS-Adobe-3.0 EPSF-3.0"), "must emit an EPS header")
        #expect(ps.contains("%%BoundingBox:"), "must emit a bounding box comment")
    }

    @Test func fillEmitsColorAndFill() throws {
        var c = GraphicsContext()
        c.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        c.fill(Rect(x: 10, y: 10, width: 30, height: 20))
        let ps = try PostScriptRenderer().render(c)
        #expect(ps.contains("setrgbcolor"), "a fill must set a color")
        #expect(ps.contains("\nfill\n") || ps.hasSuffix("fill\n"), "a winding fill must emit `fill`")
        #expect(ps.contains("moveto"), "the rect path must emit moveto")
        #expect(ps.contains("lineto"), "the rect path must emit lineto")
    }

    @Test func evenOddFillEmitsEofill() throws {
        var c = GraphicsContext()
        c.setFillColor(.white)
        var path = Path(rect: Rect(x: 10, y: 10, width: 40, height: 40))
        path.addRect(Rect(x: 20, y: 20, width: 20, height: 20))
        c.addPath(path)
        c.fillPath(using: .evenOdd)
        let ps = try PostScriptRenderer().render(c)
        #expect(ps.contains("eofill"), "an even-odd fill must emit `eofill`, not `fill`")
    }

    @Test func strokeEmitsLineWidthAndStroke() throws {
        var c = GraphicsContext()
        c.setStrokeColor(Color(red: 0, green: 0, blue: 1, alpha: 1))
        c.setLineWidth(5)
        c.move(to: Point(x: 2, y: 2))
        c.addLine(to: Point(x: 30, y: 30))
        c.strokePath()
        let ps = try PostScriptRenderer().render(c)
        #expect(ps.contains("5.0 setlinewidth") || ps.contains("5 setlinewidth"), "stroke must emit the line width")
        #expect(ps.contains("stroke"), "stroke must emit `stroke`")
    }

    @Test func clipEmitsClip() throws {
        var c = GraphicsContext()
        c.addRect(Rect(x: 5, y: 5, width: 20, height: 20))
        c.clip()
        c.setFillColor(.white)
        c.fill(Rect(x: 0, y: 0, width: 40, height: 40))
        let ps = try PostScriptRenderer().render(c)
        #expect(ps.contains("clip"), "a clip must emit `clip`")
    }

    @Test func curveEmitsCurveto() throws {
        var c = GraphicsContext()
        c.setFillColor(.white)
        c.move(to: Point(x: 10, y: 10))
        c.addCurve(to: Point(x: 40, y: 40), control1: Point(x: 20, y: 10), control2: Point(x: 40, y: 20))
        c.closeSubpath()
        c.fillPath()
        let ps = try PostScriptRenderer().render(c)
        #expect(ps.contains("curveto"), "a cubic curve must emit `curveto`")
    }
}
