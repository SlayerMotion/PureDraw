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

    @Test("GSUB ligature substitution yields component-to-ligature rules")
    func gsubLigature() throws {
        let font = try Font(data: GsubFont.build())
        let ligatures = font.ligatures()
        #expect(ligatures == [LigatureSubstitution(components: [1, 2], ligatureGlyph: 3)])
    }

    @Test("a font without GSUB has no ligatures")
    func noLigatures() throws {
        let font = try Font(data: MiniFont.build())
        #expect(font.ligatures().isEmpty)
    }

    @Test("GSUB single substitution format 2 maps glyphs for a feature")
    func gsubSingleFormat2() throws {
        let font = try Font(data: GsubSingleFont.build())
        #expect(font.singleSubstitutions(feature: "init") == [1: 5])
        #expect(font.singleSubstitutions(feature: "medi").isEmpty) // feature absent
    }

    @Test("GSUB single substitution format 1 adds a delta")
    func gsubSingleFormat1() throws {
        let font = try Font(data: GsubSingleFont1.build())
        #expect(font.singleSubstitutions(feature: "init") == [1: 5])
    }

    @Test("a font without GSUB has no single substitutions")
    func noSingleSubstitutions() throws {
        #expect(try Font(data: MiniFont.build()).singleSubstitutions(feature: "init").isEmpty)
    }

    @Test("required ligatures under rlig are read like liga")
    func gsubRligLigature() throws {
        let font = try Font(data: GsubRligFont.build())
        #expect(font.ligatures() == [LigatureSubstitution(components: [1, 2], ligatureGlyph: 3)])
    }

    @Test("GPOS mark-to-base attachment yields anchor offsets")
    func gposMarkBase() throws {
        let marks = try Font(data: MarkFont.build()).markAttachment()
        #expect(!marks.isEmpty)
        #expect(marks.isMark(3))
        #expect(!marks.isMark(1))
        // base anchor (300, 500) minus mark anchor (100, 200) = (200, 300).
        #expect(marks.offset(base: 1, mark: 3) == MarkAttachment.Point(x: 200, y: 300))
        #expect(marks.offset(base: 1, mark: 99) == nil) // unknown mark
        #expect(marks.offset(base: 99, mark: 3) == nil) // unknown base
    }

    @Test("GPOS mark-to-mark attachment yields anchor offsets")
    func gposMarkMark() throws {
        let marks = try Font(data: MarkMarkFont.build()).markMarkAttachment()
        #expect(!marks.isEmpty)
        #expect(marks.isMark(3)) // the attaching (second) mark
        #expect(!marks.isMark(2)) // the mark it rides on is a base here
        // riding-mark anchor (300, 500) minus attaching-mark anchor (100, 200) = (200, 300).
        #expect(marks.offset(base: 2, mark: 3) == MarkAttachment.Point(x: 200, y: 300))
        #expect(marks.offset(base: 2, mark: 99) == nil)
        #expect(marks.offset(base: 99, mark: 3) == nil)
        // The mark feature is separate: a mkmk-only font carries no mark-to-base.
        #expect(try Font(data: MarkMarkFont.build()).markAttachment().isEmpty)
    }

    @Test("GSUB chaining context substitution resolves nested single substitutions")
    func gsubChainContext() throws {
        let rules = try Font(data: ChainContextFont.build()).chainingSubstitutions(feature: "calt")
        #expect(rules.count == 1)
        let rule = rules[0]
        #expect(rule.backtrack == [Set([1])])
        #expect(rule.input == [Set([2])])
        #expect(rule.lookahead.isEmpty)
        #expect(rule.actions.count == 1)
        #expect(rule.actions[0].sequenceIndex == 0)
        #expect(rule.actions[0].mapping == [2: 9])
        #expect(rule.ignoreMarks) // the lookup carries the IgnoreMarks flag
        // Glyph 2 substitutes to 9 only when preceded by glyph 1.
        #expect(rule.matches([1, 2], at: 1))
        #expect(!rule.matches([3, 2], at: 1))
        #expect(!rule.matches([2], at: 0))
        // A different feature carries no chaining rules.
        #expect(try Font(data: ChainContextFont.build()).chainingSubstitutions(feature: "rclt").isEmpty)
    }

    @Test("GDEF glyph class identifies mark glyphs")
    func gdefMarkClass() throws {
        let font = try Font(data: GdefFont.build())
        #expect(font.isMarkGlyph(2)) // glyph 2 is class 3 (mark)
        #expect(!font.isMarkGlyph(1)) // glyph 1 is class 1 (base)
        #expect(!font.isMarkGlyph(0)) // unclassified
        #expect(try !Font(data: MiniFont.build()).isMarkGlyph(2)) // no GDEF
    }

    @Test("GPOS cursive attachment yields entry and exit anchors")
    func gposCursive() throws {
        let cursive = try Font(data: CursiveFont.build()).cursiveAttachment()
        #expect(!cursive.isEmpty)
        #expect(cursive.exit(1) == CursiveAttachment.Point(x: 700, y: 50)) // glyph 1 exits here
        #expect(cursive.entry(2) == CursiveAttachment.Point(x: 0, y: 50)) // glyph 2 enters here
        #expect(cursive.entry(1) == nil) // glyph 1 has a null entry
        #expect(cursive.exit(2) == nil) // glyph 2 has a null exit
        #expect(cursive.entry(99) == nil)
    }

    @Test("a font without GPOS mark positioning has empty attachment")
    func noMarks() throws {
        #expect(try Font(data: MiniFont.build()).markAttachment().isEmpty)
        #expect(try Font(data: MiniFont.build()).markMarkAttachment().isEmpty)
        #expect(try Font(data: MiniFont.build()).cursiveAttachment().isEmpty)
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

/// A minimal TrueType font with a GSUB `liga` feature whose type-4 lookup is a
/// LigatureSubst format 1 subtable: glyphs (1, 2) form ligature glyph 3.
private enum GsubFont {
    static func build() -> [UInt8] {
        // GSUB layout (offsets relative to the table start):
        //   0  header (10)        scriptList=10, featureList=12, lookupList=26
        //   10 scriptList (2)
        //   12 featureList (14)   feature 'liga' -> lookup 0
        //   26 lookupList (12)    lookup type 4, subtable at +8 (->38)
        //   38 LigatureSubst (8)  coverage +8, ligatureSet +14
        //   46 coverage (6)       glyph 1
        //   52 ligatureSet (4)    one ligature at +4
        //   56 ligature (6)       ligatureGlyph 3, componentCount 2, component 2
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gsub += be16(0)
        gsub += be16(1) + Array("liga".utf8) + be16(8)
        gsub += be16(0) + be16(1) + be16(0)
        gsub += be16(1) + be16(4)
        gsub += be16(4) + be16(0) + be16(1) + be16(8) // lookup: type 4, flag, subtableCount, offset
        gsub += be16(1) + be16(8) + be16(1) + be16(14) // LigatureSubst f1: format, coverage, setCount, setOffset
        gsub += be16(1) + be16(1) + be16(1) // coverage f1: glyph 1
        gsub += be16(1) + be16(4) // ligatureSet: count, ligature offset
        gsub += be16(3) + be16(2) + be16(2) // ligature: glyph 3, componentCount 2, component 2

        return assemble(extra: ("GSUB", gsub))
    }
}

/// As GsubFont, but the feature is `rlig` (required ligatures) instead of
/// `liga`, to confirm both feature tags are read.
private enum GsubRligFont {
    static func build() -> [UInt8] {
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gsub += be16(0)
        gsub += be16(1) + Array("rlig".utf8) + be16(8)
        gsub += be16(0) + be16(1) + be16(0)
        gsub += be16(1) + be16(4)
        gsub += be16(4) + be16(0) + be16(1) + be16(8)
        gsub += be16(1) + be16(8) + be16(1) + be16(14)
        gsub += be16(1) + be16(1) + be16(1)
        gsub += be16(1) + be16(4)
        gsub += be16(3) + be16(2) + be16(2)
        return assemble(extra: ("GSUB", gsub))
    }
}

/// A minimal TrueType font with a GSUB `init` feature whose type-1 lookup is a
/// SingleSubst format 2 subtable: glyph 1 substitutes to glyph 5.
private enum GsubSingleFont {
    static func build() -> [UInt8] {
        // GSUB layout (offsets relative to the table start):
        //   0  header (10)        scriptList=10, featureList=12, lookupList=26
        //   10 scriptList (2)
        //   12 featureList (14)   feature 'init' -> lookup 0
        //   26 lookupList (12)    lookup type 1, subtable at +8 (->38)
        //   38 SingleSubst f2 (8) coverage +8, glyphCount 1, substitute 5
        //   46 coverage (6)       glyph 1
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gsub += be16(0)
        gsub += be16(1) + Array("init".utf8) + be16(8)
        gsub += be16(0) + be16(1) + be16(0)
        gsub += be16(1) + be16(4)
        gsub += be16(1) + be16(0) + be16(1) + be16(8) // lookup: type 1, flag, subtableCount, offset
        gsub += be16(2) + be16(8) + be16(1) + be16(5) // SingleSubst f2: format, coverage, glyphCount, substitute
        gsub += be16(1) + be16(1) + be16(1) // coverage f1: glyph 1
        return assemble(extra: ("GSUB", gsub))
    }
}

/// A minimal TrueType font with a GSUB `init` feature whose type-1 lookup is a
/// SingleSubst format 1 subtable: a delta of 4 maps glyph 1 to glyph 5.
private enum GsubSingleFont1 {
    static func build() -> [UInt8] {
        // As GsubSingleFont, but the subtable is format 1 (6 bytes), coverage +6.
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gsub += be16(0)
        gsub += be16(1) + Array("init".utf8) + be16(8)
        gsub += be16(0) + be16(1) + be16(0)
        gsub += be16(1) + be16(4)
        gsub += be16(1) + be16(0) + be16(1) + be16(8)
        gsub += be16(1) + be16(6) + be16(4) // SingleSubst f1: format, coverage offset, delta 4
        gsub += be16(1) + be16(1) + be16(1) // coverage f1: glyph 1
        return assemble(extra: ("GSUB", gsub))
    }
}

/// A minimal TrueType font with a GPOS `mark` feature whose type-4 lookup is a
/// MarkBasePos subtable: mark glyph 3 (class 0, anchor 100,200) attaches to base
/// glyph 1 (class-0 anchor 300,500), so the offset is (200, 300).
private enum MarkFont {
    static func build() -> [UInt8] {
        // GPOS layout (offsets relative to the table start):
        //   0  header (10)        scriptList=10, featureList=12, lookupList=26
        //   10 scriptList (2)
        //   12 featureList (14)   feature 'mark' -> lookup 0
        //   26 lookupList (12)    lookup type 4, subtable at +8 (->38)
        //   38 MarkBasePos        header(12), markCov +12, baseCov +18,
        //                         markArray +24, baseArray +36
        var gpos: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gpos += be16(0)
        gpos += be16(1) + Array("mark".utf8) + be16(8)
        gpos += be16(0) + be16(1) + be16(0)
        gpos += be16(1) + be16(4)
        gpos += be16(4) + be16(0) + be16(1) + be16(8) // lookup: type 4
        gpos += be16(1) + be16(12) + be16(18) + be16(1) + be16(24) + be16(36) // MarkBasePos header
        gpos += be16(1) + be16(1) + be16(3) // markCoverage: glyph 3
        gpos += be16(1) + be16(1) + be16(1) // baseCoverage: glyph 1
        gpos += be16(1) + be16(0) + be16(6) // markArray: count, class 0, anchorOffset 6
        gpos += be16(1) + be16(100) + be16(200) // mark anchor (format 1)
        gpos += be16(1) + be16(4) // baseArray: count, anchorOffset 4
        gpos += be16(1) + be16(300) + be16(500) // base anchor (format 1)
        return assemble(extra: ("GPOS", gpos))
    }
}

private enum MarkMarkFont {
    static func build() -> [UInt8] {
        // Same layout as MarkFont, but the feature is 'mkmk' and the lookup is
        // type 6 (MarkMarkPos), which shares format 1 with MarkBasePos. mark1 is
        // the attaching (second) mark, glyph 3; mark2 is the mark it rides on,
        // glyph 2.
        var gpos: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gpos += be16(0)
        gpos += be16(1) + Array("mkmk".utf8) + be16(8)
        gpos += be16(0) + be16(1) + be16(0)
        gpos += be16(1) + be16(4)
        gpos += be16(6) + be16(0) + be16(1) + be16(8) // lookup: type 6
        gpos += be16(1) + be16(12) + be16(18) + be16(1) + be16(24) + be16(36) // MarkMarkPos header
        gpos += be16(1) + be16(1) + be16(3) // mark1Coverage: glyph 3
        gpos += be16(1) + be16(1) + be16(2) // mark2Coverage: glyph 2
        gpos += be16(1) + be16(0) + be16(6) // mark1Array: count, class 0, anchorOffset 6
        gpos += be16(1) + be16(100) + be16(200) // mark1 anchor (format 1)
        gpos += be16(1) + be16(4) // mark2Array: count, anchorOffset 4
        gpos += be16(1) + be16(300) + be16(500) // mark2 anchor (format 1)
        return assemble(extra: ("GPOS", gpos))
    }
}

private enum GdefFont {
    static func build() -> [UInt8] {
        // GDEF 1.0 with a GlyphClassDef (format 2): glyph 1 is a base (class 1),
        // glyph 2 is a mark (class 3).
        var gdef: [UInt8] = be16(1) + be16(0) // version 1.0
        gdef += be16(12) // glyphClassDefOffset
        gdef += be16(0) + be16(0) + be16(0) // attachList, ligCaretList, markAttachClassDef
        gdef += be16(2) + be16(2) // ClassDef format 2, 2 ranges
        gdef += be16(1) + be16(1) + be16(1) // glyph 1 -> class 1 (base)
        gdef += be16(2) + be16(2) + be16(3) // glyph 2 -> class 3 (mark)
        return assemble(extra: ("GDEF", gdef))
    }
}

private enum ChainContextFont {
    static func build() -> [UInt8] {
        // GSUB with a `calt` feature -> one chaining-context lookup (type 6,
        // format 3): glyph 2, when preceded by glyph 1, is substituted by the
        // nested single-substitution lookup (type 1) to glyph 9. Offsets are
        // relative to each subtable's start. Byte map:
        //   0  header(10)        scriptList 10, featureList 12, lookupList 26
        //   10 scriptList(2)
        //   12 featureList(14)   'calt' -> lookup index 0
        //   26 lookupList(6)     lookup 0 (chain) at +6, lookup 1 (single) at +44
        //   32 lookup 0          type 6, subtable at +8 (-> 40)
        //   40 chain subtable    backtrack cov +18, input cov +24
        //   58 backtrack cov     glyph 1
        //   64 input cov         glyph 2
        //   70 lookup 1          type 1, subtable at +8 (-> 78)
        //   78 single subst      format 2, coverage +8, substitute glyph 9
        //   86 single cov        glyph 2
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gsub += be16(0) // scriptList
        gsub += be16(1) + Array("calt".utf8) + be16(8) // featureList: 'calt' -> feature at +8
        gsub += be16(0) + be16(1) + be16(0) // feature: lookupIndex 0
        gsub += be16(2) + be16(6) + be16(44) // lookupList: 2 lookups
        gsub += be16(6) + be16(8) + be16(1) + be16(8) // lookup 0: type 6, IgnoreMarks flag, subtable +8
        gsub += be16(3) + be16(1) + be16(18) + be16(1) + be16(24) + be16(0) + be16(1) + be16(0) + be16(1) // chain fmt3
        gsub += be16(1) + be16(1) + be16(1) // backtrack coverage: glyph 1
        gsub += be16(1) + be16(1) + be16(2) // input coverage: glyph 2
        gsub += be16(1) + be16(0) + be16(1) + be16(8) // lookup 1: type 1, subtable +8
        gsub += be16(2) + be16(8) + be16(1) + be16(9) // single subst format 2 -> glyph 9
        gsub += be16(1) + be16(1) + be16(2) // single subst coverage: glyph 2
        return assemble(extra: ("GSUB", gsub))
    }
}

private enum CursiveFont {
    static func build() -> [UInt8] {
        // GPOS with one CursivePos (type 3) subtable covering glyphs 1 and 2:
        // glyph 1 exits at (700, 50) with a null entry; glyph 2 enters at (0, 50)
        // with a null exit. Offsets are relative to the subtable start (byte 38).
        var gpos: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gpos += be16(0) // scriptList
        gpos += be16(1) + Array("curs".utf8) + be16(8) // featureList: 'curs' -> lookup 0
        gpos += be16(0) + be16(1) + be16(0) // feature
        gpos += be16(1) + be16(4) // lookupList
        gpos += be16(3) + be16(0) + be16(1) + be16(8) // lookup: type 3
        gpos += be16(1) + be16(14) + be16(2) // CursivePos: format, coverage +14, entryExitCount 2
        gpos += be16(0) + be16(22) // glyph 1: entry null, exit +22
        gpos += be16(28) + be16(0) // glyph 2: entry +28, exit null
        gpos += be16(1) + be16(2) + be16(1) + be16(2) // coverage: glyphs 1, 2
        gpos += be16(1) + be16(700) + be16(50) // glyph 1 exit anchor
        gpos += be16(1) + be16(0) + be16(50) // glyph 2 entry anchor
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
