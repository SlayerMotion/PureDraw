@testable import Core
import Testing

@Suite("OpenType Layout parsing (PureDraw#140 first slice)")
struct OpenTypeLayoutTests {
    @Test("Coverage format 1 maps covered glyphs to their index")
    func coverageFormat1() throws {
        // format 1: format=1, glyphCount=3, glyphs [5, 9, 12].
        let bytes = be16(1) + be16(3) + be16(5) + be16(9) + be16(12)
        let coverage = try #require(OpenTypeCoverage(data: bytes, offset: 0))
        #expect(coverage.index(forGlyph: 5) == 0)
        #expect(coverage.index(forGlyph: 9) == 1)
        #expect(coverage.index(forGlyph: 12) == 2)
        #expect(coverage.index(forGlyph: 6) == nil)
        #expect(coverage.count == 3)
    }

    @Test("Coverage format 2 maps ranges to running indices")
    func coverageFormat2() throws {
        // format 2, one range: 10..12 starting at coverage index 0.
        let bytes = be16(2) + be16(1) + be16(10) + be16(12) + be16(0)
        let coverage = try #require(OpenTypeCoverage(data: bytes, offset: 0))
        #expect(coverage.index(forGlyph: 10) == 0)
        #expect(coverage.index(forGlyph: 11) == 1)
        #expect(coverage.index(forGlyph: 12) == 2)
        #expect(coverage.index(forGlyph: 13) == nil)
    }

    @Test("ClassDef format 1 assigns classes from a start glyph")
    func classDefFormat1() throws {
        // format 1, startGlyph=4, classes [1, 0, 2].
        let bytes = be16(1) + be16(4) + be16(3) + be16(1) + be16(0) + be16(2)
        let classDef = try #require(OpenTypeClassDef(data: bytes, offset: 0))
        #expect(classDef.classValue(forGlyph: 4) == 1)
        #expect(classDef.classValue(forGlyph: 5) == 0) // explicit class 0
        #expect(classDef.classValue(forGlyph: 6) == 2)
        #expect(classDef.classValue(forGlyph: 99) == 0) // unlisted defaults to 0
    }

    @Test("ClassDef format 2 assigns classes by range")
    func classDefFormat2() throws {
        // format 2, one range: 20..22 -> class 3.
        let bytes = be16(2) + be16(1) + be16(20) + be16(22) + be16(3)
        let classDef = try #require(OpenTypeClassDef(data: bytes, offset: 0))
        #expect(classDef.classValue(forGlyph: 20) == 3)
        #expect(classDef.classValue(forGlyph: 22) == 3)
        #expect(classDef.classValue(forGlyph: 23) == 0)
    }

    @Test("the legacy kern table yields pair adjustments")
    func legacyKern() throws {
        let font = try Font(data: KernFont.build())
        let kerning = font.kerningMap()
        #expect(!kerning.isEmpty)
        #expect(kerning.adjustment(firstGlyph: 1, secondGlyph: 1) == -40)
        #expect(kerning.adjustment(firstGlyph: 1, secondGlyph: 0) == 0) // unkerned pair
    }

    @Test("GPOS PairPos format 1 yields pair adjustments and is preferred")
    func gposPairPos() throws {
        let font = try Font(data: GposFont.build())
        let kerning = font.kerningMap()
        #expect(!kerning.isEmpty)
        #expect(kerning.adjustment(firstGlyph: 1, secondGlyph: 2) == -30)
        #expect(kerning.adjustment(firstGlyph: 2, secondGlyph: 1) == 0)
    }

    @Test("GPOS PairPos format 2 resolves class-based pair adjustments")
    func gposPairPosFormat2() throws {
        let font = try Font(data: GposFont2.build())
        let kerning = font.kerningMap()
        #expect(!kerning.isEmpty)
        #expect(kerning.adjustment(firstGlyph: 1, secondGlyph: 2) == -25)
        #expect(kerning.adjustment(firstGlyph: 2, secondGlyph: 1) == 0) // glyph 2 not covered as first
    }

    @Test("a font without a kern table has an empty kerning map")
    func noKern() throws {
        let font = try Font(data: MiniFont.build())
        #expect(font.kerningMap().isEmpty)
    }
}

private func be16(_ value: Int) -> [UInt8] {
    [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
}

private func be32(_ value: Int) -> [UInt8] {
    [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
}

/// A minimal TrueType font carrying a Microsoft format-0 `kern` table with one
/// horizontal pair (glyph 1, glyph 1) of -40 font units. The required tables
/// mirror the MiniFont fixture.
private enum KernFont {
    static func build() -> [UInt8] {
        var head: [UInt8] = []
        head += be32(0x0001_0000) + be32(0) + be32(0) + be32(0x5F0F_3CF5)
        head += be16(0) + be16(1000) // flags, unitsPerEm
        head += [UInt8](repeating: 0, count: 16)
        head += be16(0) + be16(0) + be16(500) + be16(500)
        head += be16(0) + be16(8) + be16(2) + be16(0) + be16(0)

        var maxp: [UInt8] = be32(0x0001_0000) + be16(2)
        maxp += [UInt8](repeating: 0, count: 26)

        var hhea: [UInt8] = be32(0x0001_0000) + be16(800) + be16(0xFF38)
        hhea += [UInt8](repeating: 0, count: 24) + be16(2)

        let hmtx = be16(500) + be16(0) + be16(600) + be16(0)

        var cmap: [UInt8] = be16(0) + be16(1)
        cmap += be16(3) + be16(1) + be32(12)
        cmap += be16(4) + be16(32) + be16(0)
        cmap += be16(4) + be16(4) + be16(1) + be16(0)
        cmap += be16(0x41) + be16(0xFFFF) + be16(0) + be16(0x41) + be16(0xFFFF)
        cmap += be16(0xFFC0) + be16(1) + be16(0) + be16(0)

        var glyf: [UInt8] = be16(1) + be16(0) + be16(0) + be16(500) + be16(500)
        glyf += be16(3) + be16(0) + [1, 1, 1, 1]
        glyf += be16(0) + be16(500) + be16(0) + be16(0xFE0C) + be16(0) + be16(0) + be16(500) + be16(0)

        let loca = be16(0) + be16(0) + be16(glyf.count / 2)

        // Microsoft kern: version 0, 1 subtable; subtable version 0, length 20,
        // coverage 0x0001 (horizontal, format 0); one pair (1,1) = -40.
        var kern: [UInt8] = be16(0) + be16(1)
        kern += be16(0) + be16(20) + be16(0x0001)
        kern += be16(1) + be16(6) + be16(0) + be16(0) // nPairs, searchRange, entrySelector, rangeShift
        kern += be16(1) + be16(1) + be16(0xFFD8) // left, right, value (-40)

        return assemble(extra: ("kern", kern))
    }
}

/// A minimal TrueType font carrying a GPOS table with one `kern` feature whose
/// single type-2 lookup is a PairPos format 1 subtable: pair (glyph 1, glyph 2)
/// with x advance -30 font units. Offsets are laid out by hand (see comments).
private enum GposFont {
    static func build() -> [UInt8] {
        // GPOS layout (offsets relative to the table start):
        //   0  header (10)         scriptList=10, featureList=12, lookupList=26
        //   10 scriptList (2)      scriptCount = 0
        //   12 featureList (14)    feature 'kern' -> table at +8, lookup index 0
        //   26 lookupList (12)     lookup at +4: type 2, one subtable at +8
        //   38 PairPos f1 (12)     coverage at +12, pairSet at +18, valueFormat1 = x advance
        //   50 coverage (6)        format 1, glyph 1
        //   56 pairSet (6)         second glyph 2, x advance -30
        var gpos: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gpos += be16(0) // scriptList: scriptCount 0
        gpos += be16(1) + Array("kern".utf8) + be16(8) // featureList: count, record tag + offset
        gpos += be16(0) + be16(1) + be16(0) // feature: params, lookupIndexCount, index 0
        gpos += be16(1) + be16(4) // lookupList: count, lookup offset
        gpos += be16(2) + be16(0) + be16(1) + be16(8) // lookup: type 2, flag, subtableCount, offset
        gpos += be16(1) + be16(12) + be16(0x0004) + be16(0) + be16(1) + be16(18) // PairPos f1
        gpos += be16(1) + be16(1) + be16(1) // coverage f1: format, count, glyph 1
        gpos += be16(1) + be16(2) + be16(0xFFE2) // pairSet: count, second glyph 2, x advance -30

        return assemble(extra: ("GPOS", gpos))
    }
}

/// A minimal TrueType font with a GPOS `kern` feature whose type-2 lookup is a
/// PairPos format 2 (class-based) subtable: first glyph 1 (class 1), second
/// glyph 2 (class 1), class pair (1,1) = x advance -25 font units.
private enum GposFont2 {
    static func build() -> [UInt8] {
        // GPOS layout (offsets relative to the table start):
        //   0  header (10)        scriptList=10, featureList=12, lookupList=26
        //   10 scriptList (2)
        //   12 featureList (14)   feature 'kern' -> lookup 0
        //   26 lookupList (12)    lookup type 2, subtable at +8 (->38)
        //   38 PairPos f2 (16)    coverage +24, classDef1 +30, classDef2 +38, 2x2 classes
        //   54 matrix (8)         class pair (1,1) = -25
        //   62 coverage (6)       glyph 1
        //   68 classDef1 (8)      glyph 1 -> class 1
        //   76 classDef2 (8)      glyph 2 -> class 1
        var gpos: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gpos += be16(0)
        gpos += be16(1) + Array("kern".utf8) + be16(8)
        gpos += be16(0) + be16(1) + be16(0)
        gpos += be16(1) + be16(4)
        gpos += be16(2) + be16(0) + be16(1) + be16(8)
        gpos += be16(2) + be16(24) + be16(0x0004) + be16(0) + be16(30) + be16(38) + be16(2) + be16(2)
        gpos += be16(0) + be16(0) + be16(0) + be16(0xFFE7) // matrix: (0,0),(0,1),(1,0),(1,1)=-25
        gpos += be16(1) + be16(1) + be16(1) // coverage f1: glyph 1
        gpos += be16(1) + be16(1) + be16(1) + be16(1) // classDef1 f1: glyph 1 -> class 1
        gpos += be16(1) + be16(2) + be16(1) + be16(1) // classDef2 f1: glyph 2 -> class 1

        return assemble(extra: ("GPOS", gpos))
    }
}

/// Builds a minimal valid TrueType font (two glyphs, 'A' mapped) plus one extra
/// table, shared by the kern and GPOS fixtures.
private func assemble(extra: (tag: String, data: [UInt8])) -> [UInt8] {
    var head: [UInt8] = []
    head += be32(0x0001_0000) + be32(0) + be32(0) + be32(0x5F0F_3CF5)
    head += be16(0) + be16(1000)
    head += [UInt8](repeating: 0, count: 16)
    head += be16(0) + be16(0) + be16(500) + be16(500)
    head += be16(0) + be16(8) + be16(2) + be16(0) + be16(0)

    var maxp: [UInt8] = be32(0x0001_0000) + be16(2)
    maxp += [UInt8](repeating: 0, count: 26)

    var hhea: [UInt8] = be32(0x0001_0000) + be16(800) + be16(0xFF38)
    hhea += [UInt8](repeating: 0, count: 24) + be16(2)

    let hmtx = be16(500) + be16(0) + be16(600) + be16(0)

    var cmap: [UInt8] = be16(0) + be16(1)
    cmap += be16(3) + be16(1) + be32(12)
    cmap += be16(4) + be16(32) + be16(0)
    cmap += be16(4) + be16(4) + be16(1) + be16(0)
    cmap += be16(0x41) + be16(0xFFFF) + be16(0) + be16(0x41) + be16(0xFFFF)
    cmap += be16(0xFFC0) + be16(1) + be16(0) + be16(0)

    var glyf: [UInt8] = be16(1) + be16(0) + be16(0) + be16(500) + be16(500)
    glyf += be16(3) + be16(0) + [1, 1, 1, 1]
    glyf += be16(0) + be16(500) + be16(0) + be16(0xFE0C) + be16(0) + be16(0) + be16(500) + be16(0)

    let loca = be16(0) + be16(0) + be16(glyf.count / 2)

    var tables: [(tag: String, data: [UInt8])] = [
        ("cmap", cmap), ("glyf", glyf), ("head", head), ("hhea", hhea),
        ("hmtx", hmtx), ("loca", loca), ("maxp", maxp),
    ]
    tables.append(extra)
    tables.sort { $0.tag < $1.tag }

    var font: [UInt8] = be32(0x0001_0000)
    font += be16(tables.count) + be16(0) + be16(0) + be16(0)
    var offset = 12 + tables.count * 16
    for table in tables {
        font += Array(table.tag.utf8) + be32(0) + be32(offset) + be32(table.data.count)
        offset += table.data.count
    }
    for table in tables {
        font += table.data
    }
    return font
}
