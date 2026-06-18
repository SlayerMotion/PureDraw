//
//  SbixFontTests.swift
//  PureDraw
//
//  Embedded bitmap glyphs via the Apple sbix table (PureDraw #80): a PNG strike is attached to
//  MiniFont's 'A' glyph, the font is parsed, and Font.glyphBitmap(forGlyph:) must decode that
//  PNG back to the exact pixels (through the PNG decoder from #103). Glyphs without a strike,
//  and a font with no sbix table, return nil.
//

import Core
import Testing

struct SbixFontTests {
    @Test func decodesSbixPNGGlyph() throws {
        let pixels: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255,
            128, 64, 32, 200, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 255,
        ]
        let png = storedPNG(width: 4, height: 2, rgba: pixels)
        let sfnt = sfntWithSbix(MiniFont.build(), pngForGlyph1: png)
        let font = try Font(data: sfnt)
        let glyphA = try #require(font.glyphIndex(for: "A")) // glyph 1 in MiniFont

        let bitmap = try #require(font.glyphBitmap(forGlyph: glyphA), "sbix glyph should decode to a bitmap")
        #expect(bitmap.width == 4 && bitmap.height == 2)
        #expect(bitmap.data == pixels, "the decoded sbix PNG must match the embedded pixels")

        #expect(font.glyphBitmap(forGlyph: 0) == nil, "the empty .notdef strike returns nil")
        let plain = try Font(data: MiniFont.build())
        #expect(plain.glyphBitmap(forGlyph: glyphA) == nil, "a font without sbix returns nil")
    }

    // MARK: - sbix + sfnt + PNG assembly (decoder ignores chunk CRCs)

    /// Builds an sbix table (one PNG strike) and reassembles `sfnt` with it added. MiniFont has
    /// 2 glyphs (0 = .notdef empty, 1 = 'A' with the PNG).
    private func sfntWithSbix(_ sfnt: [UInt8], pngForGlyph1 png: [UInt8]) -> [UInt8] {
        // strike layout (offsets relative to strike base): 4 (ppem+ppi) + 3 glyph-data offsets.
        let glyphDataStart = 4 + 3 * 4 // 16
        let glyphData = be16(0) + be16(0) + Array("png ".utf8) + png // originX, originY, type, image
        var strike = be16(72) + be16(72) // ppem, ppi
        strike += be32(glyphDataStart) // glyph 0 (.notdef) offset
        strike += be32(glyphDataStart) // glyph 1 ('A') offset (== prev start)
        strike += be32(glyphDataStart + glyphData.count) // end of glyph 1
        strike += glyphData

        var sbix = be16(1) + be16(0) // version, flags
        sbix += be32(1) // numStrikes
        sbix += be32(12) // strike offset (from sbix base: 8 header + 4 offset entry)
        sbix += strike

        var tables = sfntTables(sfnt)
        tables.append((tag: "sbix", data: sbix))
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

    private func storedPNG(width: Int, height: Int, rgba: [UInt8]) -> [UInt8] {
        var raw: [UInt8] = []
        for y in 0 ..< height {
            raw.append(0) // filter: none
            raw += Array(rgba[y * width * 4 ..< (y + 1) * width * 4])
        }
        var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        appendChunk("IHDR", be32(width) + be32(height) + [8, 6, 0, 0, 0], to: &png)
        appendChunk("IDAT", zlibStored(raw), to: &png)
        appendChunk("IEND", [], to: &png)
        return png
    }

    private func appendChunk(_ type: String, _ data: [UInt8], to png: inout [UInt8]) {
        png += be32(data.count) + Array(type.utf8) + data + [0, 0, 0, 0]
    }

    private func zlibStored(_ raw: [UInt8]) -> [UInt8] {
        var s: [UInt8] = [0x78, 0x01, 1]
        let len = raw.count
        s += [UInt8(len & 0xFF), UInt8(len >> 8 & 0xFF), UInt8(~len & 0xFF), UInt8(~len >> 8 & 0xFF)] + raw
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let adler = b << 16 | a
        s += [UInt8(adler >> 24 & 0xFF), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]
        return s
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
