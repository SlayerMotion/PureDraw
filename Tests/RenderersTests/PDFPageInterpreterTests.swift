//
//  PDFPageInterpreterTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
import Renderers
import Testing

/// Replaying a PDF page's content stream reproduces it as graphics operations. These assert at the
/// operation level (avoiding the PDF y-up coordinate convention that a pixel comparison would entail):
/// the operators map to the right recorded fills, strokes, colors, and transforms, and a fill written
/// by `PDFRenderer` replays back to a matching fill.
struct PDFPageInterpreterTests {
    private func fills(_ context: GraphicsContext) -> [DrawOperation] {
        context.commands.filter { if case .fill = $0.kind { true } else { false } }
    }

    private func strokes(_ context: GraphicsContext) -> [DrawOperation] {
        context.commands.filter { if case .stroke = $0.kind { true } else { false } }
    }

    @Test func fillsWithTheStatedColor() {
        let context = PDFPageInterpreter().interpret([UInt8]("1 0 0 rg 0 0 10 20 re f".utf8))
        let fill = try? #require(fills(context).first)
        #expect(fill?.state.fillColor == Color(red: 1, green: 0, blue: 0, alpha: 1))
    }

    @Test func strokesWithColorAndLineWidth() {
        let content = "0 1 0 RG 5 w 0 0 m 10 10 l S"
        let context = PDFPageInterpreter().interpret([UInt8](content.utf8))
        let stroke = try? #require(strokes(context).first)
        #expect(stroke?.state.strokeColor == Color(red: 0, green: 1, blue: 0, alpha: 1))
        #expect(stroke?.state.lineWidth == 5)
    }

    @Test func graphicsStateStackRestoresTheCTM() {
        // Inside q/Q the CTM is scaled; after Q the fill is back at the base transform.
        let content = "1 0 0 rg q 2 0 0 2 0 0 cm 0 0 5 5 re f Q 0 0 5 5 re f"
        let context = PDFPageInterpreter().interpret([UInt8](content.utf8))
        let recorded = fills(context)
        #expect(recorded.count == 2)
        // The first fill carries the scaled CTM, the second the identity it was restored to.
        #expect(recorded.first?.state.transform == AffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0))
        #expect(recorded.last?.state.transform == .identity)
    }

    @Test func grayAndCMYKColorsAreSet() {
        let gray = PDFPageInterpreter().interpret([UInt8]("0.5 g 0 0 1 1 re f".utf8))
        #expect(fills(gray).first?.state.fillColor == Color(gray: 0.5))

        let cmyk = PDFPageInterpreter().interpret([UInt8]("0 1 1 0 k 0 0 1 1 re f".utf8))
        #expect(fills(cmyk).first?.state.fillColor == Color(cyan: 0, magenta: 1, yellow: 1, black: 0))
    }

    @Test func aFillWrittenByTheRendererReplaysBack() throws {
        var original = GraphicsContext()
        original.setFillColor(Color(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        original.fill(Rect(x: 10, y: 10, width: 30, height: 40))

        let data = try PDFRenderer(width: 100, height: 100).render(original)
        let page = try #require(PDFDocumentReader().read([UInt8](data))?.pages.first)
        let replayed = PDFPageInterpreter().interpret(page.content)

        // The replayed content reproduces a single fill in the original color.
        #expect(fills(replayed).count == 1)
        #expect(fills(replayed).first?.state.fillColor == Color(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
    }
}
