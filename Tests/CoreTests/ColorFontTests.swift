//
//  ColorFontTests.swift
//  PureDraw
//
//  Layered color glyphs via OpenType COLR/CPAL (PureDraw #79): MiniFont's 'A' glyph is turned
//  into a color glyph with two layers (glyph 1 in red, glyph 0 in blue), the font is parsed, and
//  Font.colorLayers(forGlyph:) must return those layer glyphs and palette colors in order. Glyphs
//  with no base record, and a font without COLR/CPAL, return nil.
//

import Core
import Testing

struct ColorFontTests {
    @Test func resolvesColorGlyphLayers() throws {
        let sfnt = sfntWithColor(MiniFont.build())
        let font = try Font(data: sfnt)
        let glyphA = try #require(font.glyphIndex(for: "A")) // glyph 1 in MiniFont

        let layers = try #require(font.colorLayers(forGlyph: glyphA), "the color glyph should resolve layers")
        #expect(layers.map(\.glyph) == [1, 0], "layers are returned back-to-front in COLR order")
        #expect(layers.map(\.color) == [
            Color(red: 1, green: 0, blue: 0, alpha: 1), // CPAL entry 0
            Color(red: 0, green: 0, blue: 1, alpha: 1), // CPAL entry 1
        ], "palette indices must map to the CPAL colors")

        #expect(font.colorLayers(forGlyph: 0) == nil, "a glyph with no base record returns nil")
        let plain = try Font(data: MiniFont.build())
        #expect(plain.colorLayers(forGlyph: glyphA) == nil, "a font without COLR/CPAL returns nil")
    }

    // MARK: - COLR/CPAL + sfnt assembly

    private func sfntWithColor(_ sfnt: [UInt8]) -> [UInt8] {
        // COLR v0: header (14) + one base-glyph record (6) + two layer records (4 each).
        var colr = be16(0) + be16(1) // version, numBaseGlyphRecords
        colr += be32(14) // baseGlyphRecordsOffset
        colr += be32(20) // layerRecordsOffset (14 + 6)
        colr += be16(2) // numLayerRecords
        colr += be16(1) + be16(0) + be16(2) // base record: glyph 1, firstLayer 0, 2 layers
        colr += be16(1) + be16(0) // layer 0: glyph 1, palette entry 0
        colr += be16(0) + be16(1) // layer 1: glyph 0, palette entry 1

        // CPAL v0: header (12) + colorRecordIndices[1] (2) + two BGRA color records (4 each).
        var cpal = be16(0) + be16(2) + be16(1) + be16(2) // version, numEntries, numPalettes, numColorRecords
        cpal += be32(14) // colorRecordsArrayOffset (12 + 2)
        cpal += be16(0) // colorRecordIndices[0]: palette 0 starts at record 0
        cpal += [0, 0, 255, 255] // entry 0: blue,green,red,alpha = red
        cpal += [255, 0, 0, 255] // entry 1: blue = blue

        var tables = sfntTables(sfnt)
        tables.append((tag: "COLR", data: colr))
        tables.append((tag: "CPAL", data: cpal))
        return assembleSFNT(tables, flavor: 0x0001_0000)
    }

    private func sfntTables(_ sfnt: [UInt8]) -> [(tag: String, data: [UInt8])] {
        let numTables = Int(sfnt[4]) << 8 | Int(sfnt[5])
        var tables: [(String, [UInt8])] = []
        for i in 0 ..< numTables {
            let rec = 12 + i * 16
            let tag = String(decoding: sfnt[rec ..< rec + 4], as: UTF8.self)
            let offset = beUInt32(sfnt, rec + 8), length = beUInt32(sfnt, rec + 12)
            tables.append((tag, Array(sfnt[offset ..< offset + length])))
        }
        return tables
    }

    private func assembleSFNT(_ tables: [(tag: String, data: [UInt8])], flavor: Int) -> [UInt8] {
        let sorted = tables.sorted { $0.tag < $1.tag }
        var pow2 = 1, sel = 0
        while pow2 * 2 <= sorted.count {
            pow2 *= 2
            sel += 1
        }
        let searchRange = pow2 * 16
        var out = be32(flavor) + be16(sorted.count) + be16(searchRange) + be16(sel) + be16(sorted.count * 16 - searchRange)
        var offset = 12 + sorted.count * 16
        for t in sorted {
            out += Array(t.tag.utf8) + be32(0) + be32(offset) + be32(t.data.count)
            offset += (t.data.count + 3) & ~3
        }
        for t in sorted {
            out += t.data + [UInt8](repeating: 0, count: ((t.data.count + 3) & ~3) - t.data.count)
        }
        return out
    }

    private func beUInt32(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
    }

    private func be32(_ v: Int) -> [UInt8] {
        [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }

    private func be16(_ v: Int) -> [UInt8] {
        [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }
}
