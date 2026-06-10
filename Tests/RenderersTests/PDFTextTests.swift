//
//  PDFTextTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
@testable import Renderers
import Testing

#if canImport(PDFKit)
    import PDFKit
#endif

struct PDFTextTests {
    private func textContext() throws -> GraphicsContext {
        var context = GraphicsContext()
        try context.setFont(Font(data: SVGTextTests.miniFontBytes))
        context.setFontSize(24)
        context.setFillColor(Color(red: 0, green: 0, blue: 0, alpha: 1))
        return context
    }

    @Test func embedsFontAndEmitsTextObjects() throws {
        var context = try textContext()
        context.showText("AA", at: Point(x: 20, y: 40))

        let pdf = try PDFRenderer(width: 200, height: 100).render(context)
        let text = String(decoding: pdf, as: UTF8.self)

        // The composite font and program are embedded.
        #expect(text.contains("/Subtype /Type0"))
        #expect(text.contains("/Subtype /CIDFontType2"))
        #expect(text.contains("/FontFile2"))
        #expect(text.contains("/Encoding /Identity-H"))
        #expect(text.contains("/ToUnicode"))
        // A text object shows the glyphs via Tj.
        #expect(text.contains("BT\n"))
        #expect(text.contains("Tf\n"))
        #expect(text.contains("Tj\n"))
        // Glyph 'A' is index 1 -> 2-byte code 0001.
        #expect(text.contains("<00010001> Tj"))
        // The page references the font.
        #expect(text.contains("/Font <<"))
    }

    @Test func glyphRunsLowerToOutlines() throws {
        var context = try textContext()
        context.showGlyphs([1], at: Point(x: 10, y: 40))

        let pdf = try PDFRenderer(width: 100, height: 100).render(context)
        let text = String(decoding: pdf, as: UTF8.self)
        // No source string -> outlines, not a Type0 font.
        #expect(!text.contains("/Subtype /Type0"))
        #expect(!text.contains(" Tj\n"))
        #expect(text.contains("f\n")) // a fill operator from the glyph outline
    }

    @Test func pdfKitParsesEmbeddedText() throws {
        #if canImport(PDFKit)
            var context = try textContext()
            context.showText("AA", at: Point(x: 20, y: 60))

            let data = try PDFRenderer(width: 200, height: 100).render(context)
            let document = try #require(PDFDocument(data: data), "PDFKit must accept the document")
            #expect(document.pageCount == 1)
            let page = try #require(document.page(at: 0))
            // ToUnicode maps the glyphs back to "AA"; PDFKit extracts it.
            let extracted = page.string ?? ""
            #expect(extracted.contains("AA"), "expected selectable text, got \(extracted.debugDescription)")
        #endif
    }
}
