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

extension PDFTextTests {
    @Test func embeddedFontStreamIsValidZlib() throws {
        // The FontFile2 program must be wrapped in a real zlib stream (header
        // 0x78), not Apple's raw DEFLATE, which CoreGraphics cannot decode as
        // FlateDecode (the glyphs then render as .notdef).
        var ctx = GraphicsContext()
        try ctx.setFont(Font(data: SVGTextTests.miniFontBytes))
        ctx.setFontSize(24)
        ctx.setFillColor(.black)
        ctx.showText("A", at: Point(x: 10, y: 40))
        let data = try PDFRenderer(width: 100, height: 60).render(ctx)
        let bytes = [UInt8](data)

        // Locate the FontFile2 object's stream and check the zlib header.
        let needle = Array("/Length1".utf8)
        guard let lengthOne = firstRange(of: needle, in: bytes) else {
            Issue.record("no FontFile2 object")
            return
        }
        guard let streamKeyword = firstRange(of: Array("stream\n".utf8), in: bytes, from: lengthOne) else {
            Issue.record("no stream after FontFile2")
            return
        }
        let streamStart = streamKeyword + Array("stream\n".utf8).count
        #expect(bytes[streamStart] == 0x78, "FontFile2 must start with a zlib header, got 0x\(String(bytes[streamStart], radix: 16))")
    }

    private func firstRange(of needle: [UInt8], in haystack: [UInt8], from: Int = 0) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        var i = from
        while i <= haystack.count - needle.count {
            if Array(haystack[i ..< i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }
}
