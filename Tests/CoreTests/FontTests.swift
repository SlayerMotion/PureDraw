//
//  FontTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing
import Validation

struct FontTests {
    @Test func parsesMiniFontHeader() throws {
        let font = try Font(data: MiniFont.build())
        #expect(font.unitsPerEm == 1000)
        #expect(font.numberOfGlyphs == 2)
        #expect(font.ascent == 800)
        #expect(font.descent == -200)
    }

    @Test func mapsCharactersThroughCmapFormat4() throws {
        let font = try Font(data: MiniFont.build())
        #expect(font.glyphIndex(for: "A") == 1)
        #expect(font.glyphIndex(for: "B") == nil)
        #expect(font.glyphIndex(for: " ") == nil)
    }

    @Test func readsAdvanceWidths() throws {
        let font = try Font(data: MiniFont.build())
        #expect(font.advanceWidth(forGlyph: 0) == 500)
        #expect(font.advanceWidth(forGlyph: 1) == 600)
    }

    @Test func decodesGlyphOutline() throws {
        let font = try Font(data: MiniFont.build())

        let outline = try #require(font.outline(forGlyph: 1))
        let bounds = outline.boundingBox
        #expect(bounds.minX == 0)
        #expect(bounds.minY == 0)
        #expect(bounds.maxX == 500)
        #expect(bounds.maxY == 500)

        // Glyph 0 has no contours.
        #expect(font.outline(forGlyph: 0) == nil)
        #expect(font.outline(forGlyph: 99) == nil)
    }

    @Test func rejectsGarbage() {
        #expect(throws: ValidationError.self) {
            _ = try Font(data: [0, 1, 2, 3, 4, 5])
        }
        #expect(throws: ValidationError.self) {
            _ = try Font(data: MiniFont.ascii("OTTO") + [UInt8](repeating: 0, count: 64))
        }
    }
}

/// Builds a minimal but structurally valid TrueType font: two glyphs
/// (.notdef empty, 'A' mapped to a 500x500 square), cmap format 4,
/// short loca, 1000 units per em.
enum MiniFont {
    static func build(extraTables: [(tag: String, data: [UInt8])] = []) -> [UInt8] {
        var head: [UInt8] = []
        head += be32(0x0001_0000) // version
        head += be32(0) // fontRevision
        head += be32(0) // checkSumAdjustment
        head += be32(0x5F0F_3CF5) // magic
        head += be16(0) // flags
        head += be16(1000) // unitsPerEm
        head += [UInt8](repeating: 0, count: 16) // created + modified
        head += be16(0) + be16(0) + be16(500) + be16(500) // bounds
        head += be16(0) // macStyle
        head += be16(8) // lowestRecPPEM
        head += be16(2) // fontDirectionHint
        head += be16(0) // indexToLocFormat: short
        head += be16(0) // glyphDataFormat

        var maxp: [UInt8] = []
        maxp += be32(0x0001_0000)
        maxp += be16(2) // numGlyphs
        maxp += [UInt8](repeating: 0, count: 26)

        var hhea: [UInt8] = []
        hhea += be32(0x0001_0000)
        hhea += be16(800) // ascender
        hhea += be16(0xFF38) // descender: -200
        hhea += [UInt8](repeating: 0, count: 24) // lineGap ... metricDataFormat
        hhea += be16(2) // numberOfHMetrics

        var hmtx: [UInt8] = []
        hmtx += be16(500) + be16(0) // .notdef
        hmtx += be16(600) + be16(0) // square

        var cmap: [UInt8] = []
        cmap += be16(0) + be16(1) // version, one subtable
        cmap += be16(3) + be16(1) + be32(12) // Windows Unicode BMP at offset 12
        cmap += be16(4) + be16(32) + be16(0) // format 4, length, language
        cmap += be16(4) + be16(4) + be16(1) + be16(0) // segCountX2, search params
        cmap += be16(0x41) + be16(0xFFFF) // endCode
        cmap += be16(0) // reservedPad
        cmap += be16(0x41) + be16(0xFFFF) // startCode
        cmap += be16(0xFFC0) + be16(1) // idDelta: 'A' -> 1
        cmap += be16(0) + be16(0) // idRangeOffset

        var glyf: [UInt8] = []
        glyf += be16(1) // one contour
        glyf += be16(0) + be16(0) + be16(500) + be16(500) // bounds
        glyf += be16(3) // endPtsOfContours
        glyf += be16(0) // instructionLength
        glyf += [1, 1, 1, 1] // flags: all on-curve, full deltas
        glyf += be16(0) + be16(500) + be16(0) + be16(0xFE0C) // x deltas: 0, 500, 0, -500
        glyf += be16(0) + be16(0) + be16(500) + be16(0) // y deltas

        var loca: [UInt8] = []
        loca += be16(0) + be16(0) + be16(glyf.count / 2) // short format: offset / 2

        let tables: [(tag: String, data: [UInt8])] = [
            ("cmap", cmap), ("glyf", glyf), ("head", head), ("hhea", hhea),
            ("hmtx", hmtx), ("loca", loca), ("maxp", maxp),
        ] + extraTables

        var font: [UInt8] = []
        font += be32(0x0001_0000)
        font += be16(tables.count) + be16(0) + be16(0) + be16(0)
        var offset = 12 + tables.count * 16
        for table in tables {
            font += ascii(table.tag)
            font += be32(0) // checksum, unverified
            font += be32(offset)
            font += be32(table.data.count)
            offset += table.data.count
        }
        for table in tables {
            font += table.data
        }
        return font
    }

    /// Locates a table's byte offset by walking the font directory; used by
    /// tests that corrupt specific tables.
    static func tableOffset(in font: [UInt8], tag: String) -> Int? {
        let tagBytes = Array(tag.utf8)
        let tableCount = Int(font[4]) << 8 | Int(font[5])
        for index in 0 ..< tableCount {
            let record = 12 + index * 16
            if Array(font[record ..< record + 4]) == tagBytes {
                return Int(font[record + 8]) << 24 | Int(font[record + 9]) << 16 | Int(font[record + 10]) << 8 | Int(font[record + 11])
            }
        }
        return nil
    }

    static func ascii(_ string: String) -> [UInt8] {
        Array(string.utf8)
    }

    static func be16(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    static func be32(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
