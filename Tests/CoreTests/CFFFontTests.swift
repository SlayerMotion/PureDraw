//
//  CFFFontTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing
import Validation

struct CFFFontTests {
    @Test func parsesOpenTypeCFFHeader() throws {
        let font = try Font(data: MiniCFFFont.build())
        #expect(font.unitsPerEm == 1000)
        #expect(font.numberOfGlyphs == 2)
        #expect(font.glyphIndex(for: "A") == 1)
    }

    @Test func interpretsType2CharstringIntoOutline() throws {
        let font = try Font(data: MiniCFFFont.build())

        // Glyph 1 draws a square from (100, 100) to (400, 400) via rmoveto +
        // rlineto, so the outline bounds are exactly that box.
        let outline = try #require(font.outline(forGlyph: 1))
        let bounds = outline.boundingBox
        #expect(bounds.minX == 100)
        #expect(bounds.minY == 100)
        #expect(bounds.maxX == 400)
        #expect(bounds.maxY == 400)

        // Glyph 0 is endchar only: no contour.
        #expect(font.outline(forGlyph: 0) == nil)
    }

    @Test func interpretsCurveOperators() throws {
        // Glyph 1 is a single rrcurveto, so its outline must carry a cubic.
        let font = try Font(data: MiniCFFFont.buildWithGlyph(curveGlyph()))
        let outline = try #require(font.outline(forGlyph: 1))
        let hasCurve = outline.elements.contains { element in
            if case .cubicCurve = element { return true }
            return false
        }
        #expect(hasCurve == true)
    }

    @Test func rejectsTruncatedCFF() {
        var bytes = MiniCFFFont.build()
        // Corrupt the CFF table: find it and zero its content past the header.
        if let cffOffset = MiniFont.tableOffset(in: bytes, tag: "CFF ") {
            for index in (cffOffset + 4) ..< min(cffOffset + 40, bytes.count) {
                bytes[index] = 0
            }
            #expect(throws: ValidationError.self) {
                _ = try Font(data: bytes)
            }
        } else {
            Issue.record("could not locate CFF table")
        }
    }

    // MARK: - Helpers

    private func curveGlyph() -> [UInt8] {
        // 0 0 rmoveto, then rrcurveto (10 20 30 0 10 -20), endchar.
        var bytes: [UInt8] = []
        for value in [0, 0] {
            bytes += MiniCFFFont.encodeInt(value)
        }
        bytes.append(21) // rmoveto
        for value in [10, 20, 30, 0, 10, -20] {
            bytes += MiniCFFFont.encodeInt(value)
        }
        bytes.append(8) // rrcurveto
        bytes.append(14) // endchar
        return bytes
    }
}

/// Builds a minimal but valid OpenType/CFF font: an sfnt with head, maxp,
/// hhea, hmtx, cmap, and a CFF table holding two glyphs (.notdef and a square).
enum MiniCFFFont {
    static func build() -> [UInt8] {
        buildWithGlyph(squareGlyph())
    }

    static func buildWithGlyph(_ glyph1: [UInt8]) -> [UInt8] {
        let cff = cffTable(glyph1: glyph1)

        var head: [UInt8] = []
        head += be32(0x0001_0000)
        head += be32(0)
        head += be32(0)
        head += be32(0x5F0F_3CF5)
        head += be16(0)
        head += be16(1000) // unitsPerEm
        head += [UInt8](repeating: 0, count: 16)
        head += be16(0) + be16(0) + be16(500) + be16(500)
        head += be16(0)
        head += be16(8)
        head += be16(2)
        head += be16(0) // indexToLocFormat (unused for CFF)
        head += be16(0)

        var maxp: [UInt8] = []
        maxp += be32(0x0001_0000)
        maxp += be16(2)
        maxp += [UInt8](repeating: 0, count: 26)

        var hhea: [UInt8] = []
        hhea += be32(0x0001_0000)
        hhea += be16(800)
        hhea += be16(0xFF38) // -200
        hhea += [UInt8](repeating: 0, count: 24)
        hhea += be16(2)

        var hmtx: [UInt8] = []
        hmtx += be16(500) + be16(0)
        hmtx += be16(600) + be16(0)

        var cmap: [UInt8] = []
        cmap += be16(0) + be16(1)
        cmap += be16(3) + be16(1) + be32(12)
        cmap += be16(4) + be16(32) + be16(0)
        cmap += be16(4) + be16(4) + be16(1) + be16(0)
        cmap += be16(0x41) + be16(0xFFFF)
        cmap += be16(0)
        cmap += be16(0x41) + be16(0xFFFF)
        cmap += be16(0xFFC0) + be16(1)
        cmap += be16(0) + be16(0)

        let tables: [(tag: String, data: [UInt8])] = [
            ("CFF ", cff), ("cmap", cmap), ("head", head),
            ("hhea", hhea), ("hmtx", hmtx), ("maxp", maxp),
        ]

        var font: [UInt8] = []
        font += ascii("OTTO")
        font += be16(tables.count) + be16(0) + be16(0) + be16(0)
        var offset = 12 + tables.count * 16
        for table in tables {
            font += ascii(table.tag)
            font += be32(0)
            font += be32(offset)
            font += be32(table.data.count)
            offset += table.data.count
        }
        for table in tables {
            font += table.data
        }
        return font
    }

    /// A CFF table with the standard INDEX/DICT layout and two charstrings.
    private static func cffTable(glyph1: [UInt8]) -> [UInt8] {
        let header: [UInt8] = [1, 0, 4, 1]
        let nameIndex = index([ascii("F")])
        let stringIndex = index([])
        let globalSubrIndex = index([])
        let charStrings = index([[14], glyph1]) // glyph 0 = endchar

        // CharStrings offset = everything before the CharStrings INDEX. The Top
        // DICT encodes it as a fixed 5-byte integer so its size does not depend
        // on the value.
        let topDictContent: ([UInt8]) -> [UInt8] = { offsetBytes in
            offsetBytes + [17] // operator 17 = CharStrings
        }
        let topDictIndexSize = index([topDictContent([29, 0, 0, 0, 0])]).count
        let charStringsOffset = header.count + nameIndex.count + topDictIndexSize + stringIndex.count + globalSubrIndex.count
        let offsetBytes: [UInt8] = [
            29,
            UInt8((charStringsOffset >> 24) & 0xFF),
            UInt8((charStringsOffset >> 16) & 0xFF),
            UInt8((charStringsOffset >> 8) & 0xFF),
            UInt8(charStringsOffset & 0xFF),
        ]
        let topDictIndex = index([topDictContent(offsetBytes)])

        return header + nameIndex + topDictIndex + stringIndex + globalSubrIndex + charStrings
    }

    /// Glyph 1: a square (100,100)-(400,400) via rmoveto + rlineto.
    private static func squareGlyph() -> [UInt8] {
        var bytes: [UInt8] = []
        for value in [100, 100] {
            bytes += encodeInt(value)
        }
        bytes.append(21) // rmoveto
        for value in [300, 0, 0, 300, -300, 0] {
            bytes += encodeInt(value)
        }
        bytes.append(5) // rlineto
        bytes.append(14) // endchar
        return bytes
    }

    /// A CFF INDEX over a list of objects, using one-byte offsets.
    private static func index(_ objects: [[UInt8]]) -> [UInt8] {
        if objects.isEmpty {
            return be16(0)
        }
        var offsets = [1]
        var running = 1
        for object in objects {
            running += object.count
            offsets.append(running)
        }
        var bytes = be16(objects.count)
        bytes.append(1) // offSize = 1
        for offset in offsets {
            bytes.append(UInt8(offset & 0xFF))
        }
        for object in objects {
            bytes += object
        }
        return bytes
    }

    /// Encodes a Type 2 / DICT integer operand.
    static func encodeInt(_ value: Int) -> [UInt8] {
        if value >= -107, value <= 107 {
            return [UInt8(value + 139)]
        }
        if value >= 108, value <= 1131 {
            let v = value - 108
            return [UInt8(v / 256 + 247), UInt8(v % 256)]
        }
        if value >= -1131, value <= -108 {
            let v = -value - 108
            return [UInt8(v / 256 + 251), UInt8(v % 256)]
        }
        // 16-bit shortint.
        return [28, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
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
