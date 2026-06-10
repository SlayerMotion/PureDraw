//
//  SVGTextTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

struct SVGTextTests {
    private func textContext() throws -> GraphicsContext {
        var context = GraphicsContext()
        try context.setFont(Font(data: Self.miniFont()))
        context.setFontSize(24)
        context.setFillColor(Color(red: 0, green: 0, blue: 0, alpha: 1))
        return context
    }

    /// A minimal TrueType font (two glyphs: .notdef and a 500-unit square
    /// mapped to 'A'), built here so the Renderers test target needs nothing
    /// from CoreTests.
    static let miniFontBytes: [UInt8] = miniFont()

    private static func miniFont() -> [UInt8] {
        func be16(_ v: Int) -> [UInt8] {
            [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        }
        func be32(_ v: Int) -> [UInt8] {
            [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        }

        var head: [UInt8] = []
        head += be32(0x0001_0000)
        head += be32(0) + be32(0) + be32(0x5F0F_3CF5) + be16(0)
        head += be16(1000)
        head += [UInt8](repeating: 0, count: 16)
        head += be16(0) + be16(0) + be16(500) + be16(500)
        head += be16(0) + be16(8) + be16(2) + be16(0) + be16(0)

        var maxp: [UInt8] = []
        maxp += be32(0x0001_0000) + be16(2)
        maxp += [UInt8](repeating: 0, count: 26)

        var hhea: [UInt8] = []
        hhea += be32(0x0001_0000) + be16(800) + be16(0xFF38)
        hhea += [UInt8](repeating: 0, count: 24)
        hhea += be16(2)

        var hmtx: [UInt8] = []
        hmtx += be16(500) + be16(0) + be16(600) + be16(0)

        var cmap: [UInt8] = []
        cmap += be16(0) + be16(1) + be16(3) + be16(1) + be32(12)
        cmap += be16(4) + be16(32) + be16(0)
        cmap += be16(4) + be16(4) + be16(1) + be16(0)
        cmap += be16(0x41) + be16(0xFFFF) + be16(0) + be16(0x41) + be16(0xFFFF)
        cmap += be16(0xFFC0) + be16(1) + be16(0) + be16(0)

        var glyf: [UInt8] = []
        glyf += be16(1) + be16(0) + be16(0) + be16(500) + be16(500)
        glyf += be16(3) + be16(0) + [1, 1, 1, 1]
        glyf += be16(0) + be16(500) + be16(0) + be16(0xFE0C)
        glyf += be16(0) + be16(0) + be16(500) + be16(0)

        var loca: [UInt8] = []
        loca += be16(0) + be16(0) + be16(glyf.count / 2)

        let tables: [(String, [UInt8])] = [
            ("cmap", cmap), ("glyf", glyf), ("head", head), ("hhea", hhea),
            ("hmtx", hmtx), ("loca", loca), ("maxp", maxp),
        ]
        var font: [UInt8] = []
        font += be32(0x0001_0000) + be16(tables.count) + be16(0) + be16(0) + be16(0)
        var offset = 12 + tables.count * 16
        for table in tables {
            font += Array(table.0.utf8) + be32(0) + be32(offset) + be32(table.1.count)
            offset += table.1.count
        }
        for table in tables {
            font += table.1
        }
        return font
    }

    @Test func emitsSelectableTextElement() throws {
        var context = try textContext()
        context.showText("A&A", at: Point(x: 10, y: 40))

        let svg = try SVGRenderer().render(context)
        #expect(svg.contains("<text"))
        #expect(svg.contains("x=\"10.0\" y=\"40.0\""))
        #expect(svg.contains("font-size=\"24.0\""))
        // The ampersand is XML-escaped.
        #expect(svg.contains(">A&amp;A</text>"))
        // Native text means no glyph outline <path> for the run.
        #expect(!svg.contains("<path d=\"M 10"))
    }

    @Test func glyphIndexRunsFallBackToOutlines() throws {
        var context = try textContext()
        // showGlyphs carries no source string, so it cannot be selectable text.
        context.showGlyphs([1], at: Point(x: 5, y: 30))

        let svg = try SVGRenderer().render(context)
        #expect(!svg.contains("<text"))
        #expect(svg.contains("<path"))
    }

    @Test func bitmapStillRastersTextIdentically() throws {
        // The bitmap backend lowers text to outlines regardless of the source
        // string, so a glyph run and the same text string render the same.
        var viaString = try textContext()
        viaString.showText("A", at: Point(x: 4, y: 28))

        var viaGlyph = try textContext()
        viaGlyph.showGlyphs([1], at: Point(x: 4, y: 28))

        let a = try BitmapRenderer(width: 32, height: 32).render(viaString)
        let b = try BitmapRenderer(width: 32, height: 32).render(viaGlyph)
        #expect(a.data == b.data)
        // And something was actually drawn.
        #expect(a.data.contains { $0 != 0 })
    }
}
