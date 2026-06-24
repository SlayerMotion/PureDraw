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

    @Test("GSUB multiple substitution expands a glyph into a sequence")
    func gsubMultiple() throws {
        let font = try Font(data: GsubMultipleFont.build())
        #expect(font.multipleSubstitutions(feature: "ccmp") == [1: [4, 5]])
        #expect(font.multipleSubstitutions(feature: "liga").isEmpty) // feature absent
    }

    @Test("GSUB alternate substitution lists a glyph's alternates in order")
    func gsubAlternate() throws {
        let font = try Font(data: GsubAlternateFont.build())
        #expect(font.alternateSubstitutions(feature: "aalt") == [1: [7, 8]])
        #expect(font.alternateSubstitutions(feature: "salt").isEmpty) // feature absent
    }

    @Test("a font without GSUB has no multiple or alternate substitutions")
    func noSequenceSubstitutions() throws {
        let font = try Font(data: MiniFont.build())
        #expect(font.multipleSubstitutions(feature: "ccmp").isEmpty)
        #expect(font.alternateSubstitutions(feature: "aalt").isEmpty)
    }

    @Test("a script's default language system selects its listed feature indices")
    func featureIndicesDefaultLangSys() throws {
        let font = try Font(data: LangSysFont.build())
        #expect(font.gsubFeatureIndices(script: "latn") == [0, 1])
    }

    @Test("a named language system selects its features plus the required feature")
    func featureIndicesNamedLangSys() throws {
        let font = try Font(data: LangSysFont.build())
        #expect(font.gsubFeatureIndices(script: "latn", language: "TRK ") == [0, 2])
    }

    @Test("an unknown language falls back to the script's default language system")
    func featureIndicesUnknownLanguage() throws {
        let font = try Font(data: LangSysFont.build())
        #expect(font.gsubFeatureIndices(script: "latn", language: "ZZZ ") == [0, 1])
    }

    @Test("an absent script falls back to the DFLT script")
    func featureIndicesDfltFallback() throws {
        let font = try Font(data: LangSysFont.build())
        #expect(font.gsubFeatureIndices(script: "grek") == [0]) // grek absent -> DFLT
        #expect(font.gsubFeatureIndices(script: "DFLT") == [0])
    }

    @Test("a font with no GSUB or GPOS has no active feature indices")
    func featureIndicesNoTable() throws {
        let font = try Font(data: MiniFont.build())
        #expect(font.gsubFeatureIndices(script: "latn").isEmpty)
        #expect(font.gposFeatureIndices(script: "latn").isEmpty)
    }

    @Test("several script tags resolve to the first one the font carries, else DFLT")
    func featureIndicesScriptOrder() throws {
        let font = try Font(data: LangSysFont.build())
        #expect(font.gsubFeatureIndices(scripts: ["grek", "latn"]) == [0, 1]) // grek absent -> latn present
        #expect(font.gsubFeatureIndices(scripts: ["latn", "grek"]) == [0, 1]) // latn present first
        #expect(font.gsubFeatureIndices(scripts: ["grek", "armn"]) == [0]) // both absent -> DFLT
    }

    @Test("GSUB gathering restricted to an active feature-index set drops the rest")
    func gsubFeatureRestriction() throws {
        let font = try Font(data: GsubFont.build()) // one `liga` feature at index 0
        let rule = LigatureSubstitution(components: [1, 2], ligatureGlyph: 3)
        #expect(font.ligatures() == [rule]) // unrestricted: by-tag
        #expect(font.ligatures(restrictTo: [0]) == [rule]) // feature 0 is active
        #expect(font.ligatures(restrictTo: [7]).isEmpty) // feature 0 not active -> dropped
        #expect(font.ligatures(restrictTo: []).isEmpty) // nothing active -> dropped
    }

    @Test("GPOS gathering restricted to an active feature-index set drops the rest")
    func gposFeatureRestriction() throws {
        let font = try Font(data: GposFont.build()) // one `kern` feature at index 0
        #expect(!font.kerningMap().isEmpty) // unrestricted: by-tag
        #expect(!font.kerningMap(restrictTo: [0]).isEmpty) // feature 0 is active
        #expect(font.kerningMap(restrictTo: [7]).isEmpty) // feature 0 not active -> dropped
        #expect(font.kerningMap(restrictTo: []).isEmpty) // nothing active -> dropped
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

    @Test("GSUB contextual substitution (type 5) resolves nested single substitutions")
    func gsubContext() throws {
        let rules = try Font(data: ContextFont.build()).chainingSubstitutions(feature: "calt")
        #expect(rules.count == 1)
        let rule = rules[0]
        #expect(rule.backtrack.isEmpty) // type 5 has no surrounding context
        #expect(rule.lookahead.isEmpty)
        #expect(rule.input == [Set([1]), Set([2])])
        #expect(rule.actions == [ChainingSubstitution.Action(sequenceIndex: 1, mapping: [2: 9])])
        // Glyph 2 substitutes to 9 only as the second glyph of the input (1, 2).
        #expect(rule.matches([1, 2], at: 0))
        #expect(!rule.matches([3, 2], at: 0))
    }

    @Test("GSUB reverse chaining single substitution (type 8) parses its context and substitutes")
    func gsubReverseChain() throws {
        let rules = try Font(data: ReverseChainFont.build()).reverseChainingSubstitutions(feature: "calt")
        #expect(rules.count == 1)
        let rule = rules[0]
        #expect(rule.backtrack == [Set([1])]) // glyph 2 substitutes only after glyph 1
        #expect(rule.lookahead.isEmpty)
        #expect(rule.mapping == [2: 9])
        #expect(try Font(data: ReverseChainFont.build()).reverseChainingSubstitutions(feature: "rclt").isEmpty)
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
        #expect(try Font(data: MiniFont.build()).markLigatureAttachment().isEmpty)
    }

    @Test("GPOS mark-to-ligature attachment yields per-component anchor offsets")
    func gposMarkLigature() throws {
        let attach = try Font(data: MarkLigatureFont.build()).markLigatureAttachment()
        #expect(!attach.isEmpty)
        // Mark 3 (anchor 100,200) on ligature 4: component 0 anchor 300,500 gives
        // offset (200,300); component 1 anchor 400,600 gives (300,400).
        #expect(attach.offset(ligature: 4, component: 0, mark: 3) == MarkAttachment.Point(x: 200, y: 300))
        #expect(attach.offset(ligature: 4, component: 1, mark: 3) == MarkAttachment.Point(x: 300, y: 400))
        #expect(attach.offset(ligature: 4, component: 2, mark: 3) == nil) // component out of range
        #expect(attach.offset(ligature: 9, component: 0, mark: 3) == nil) // unknown ligature
    }

    @Test("GPOS contextual positioning (type 8) resolves nested single adjustments")
    func gposContextualPositioning() throws {
        let rules = try Font(data: ContextPosFont.build()).contextualPositioning(feature: "kern")
        #expect(rules.count == 1)
        let rule = rules[0]
        #expect(rule.backtrack == [Set([1])]) // glyph 2 is adjusted only after glyph 1
        #expect(rule.input == [Set([2])])
        #expect(rule.lookahead.isEmpty)
        #expect(rule.actions == [.init(sequenceIndex: 0, adjustments: [2: GlyphAdjustment(xAdvance: -40)])])
        #expect(rule.matches([1, 2], at: 1))
        #expect(!rule.matches([3, 2], at: 1))
        #expect(try Font(data: ContextPosFont.build()).contextualPositioning(feature: "liga").isEmpty)
    }

    @Test("a font without a kern table has an empty kerning map")
    func noKern() throws {
        let font = try Font(data: MiniFont.build())
        #expect(font.kerningMap().isEmpty)
    }

    @Test("GPOS single adjustment format 1 applies one value record to every covered glyph")
    func gposSingleFormat1() throws {
        let font = try Font(data: SinglePosFont1.build())
        #expect(font.singleAdjustments(feature: "kern") == [1: GlyphAdjustment(xPlacement: 30, xAdvance: -20)])
        #expect(font.singleAdjustments(feature: "liga").isEmpty) // feature absent
    }

    @Test("GPOS single adjustment format 2 applies a value record per covered glyph")
    func gposSingleFormat2() throws {
        let font = try Font(data: SinglePosFont2.build())
        #expect(font.singleAdjustments(feature: "kern") == [1: GlyphAdjustment(xAdvance: 10), 2: GlyphAdjustment(xAdvance: -10)])
    }

    @Test("a font with no GPOS has no single adjustments")
    func noSinglePos() throws {
        #expect(try Font(data: MiniFont.build()).singleAdjustments(feature: "kern").isEmpty)
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

/// A minimal TrueType font with a GSUB `ccmp` feature whose type-2 lookup is a
/// MultipleSubst format 1 subtable: glyph 1 expands into the sequence (4, 5).
private enum GsubMultipleFont {
    static func build() -> [UInt8] {
        // GSUB layout (offsets relative to the table start):
        //   0  header (10)         scriptList=10, featureList=12, lookupList=26
        //   10 scriptList (2)
        //   12 featureList (14)    feature 'ccmp' -> lookup 0
        //   26 lookupList (12)     lookup type 2, subtable at +8 (->38)
        //   38 MultipleSubst f1 (8) coverage +8, sequenceCount 1, sequence +14
        //   46 coverage (6)        glyph 1
        //   52 sequence (6)        glyphCount 2, glyphs 4, 5
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gsub += be16(0)
        gsub += be16(1) + Array("ccmp".utf8) + be16(8)
        gsub += be16(0) + be16(1) + be16(0)
        gsub += be16(1) + be16(4)
        gsub += be16(2) + be16(0) + be16(1) + be16(8) // lookup: type 2, flag, subtableCount, offset
        gsub += be16(1) + be16(8) + be16(1) + be16(14) // MultipleSubst f1: format, coverage, seqCount, seqOffset
        gsub += be16(1) + be16(1) + be16(1) // coverage f1: glyph 1
        gsub += be16(2) + be16(4) + be16(5) // sequence: glyphCount 2, glyphs 4, 5
        return assemble(extra: ("GSUB", gsub))
    }
}

/// A minimal TrueType font with a GSUB `aalt` feature whose type-3 lookup is an
/// AlternateSubst format 1 subtable: glyph 1 has the alternates (7, 8). The
/// on-disk layout is identical to MultipleSubst format 1; only the lookup type
/// and the meaning of the glyph array differ.
private enum GsubAlternateFont {
    static func build() -> [UInt8] {
        // GSUB layout (offsets relative to the table start):
        //   0  header (10)          scriptList=10, featureList=12, lookupList=26
        //   10 scriptList (2)
        //   12 featureList (14)     feature 'aalt' -> lookup 0
        //   26 lookupList (12)      lookup type 3, subtable at +8 (->38)
        //   38 AlternateSubst f1 (8) coverage +8, alternateSetCount 1, set +14
        //   46 coverage (6)         glyph 1
        //   52 alternateSet (6)     glyphCount 2, alternates 7, 8
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gsub += be16(0)
        gsub += be16(1) + Array("aalt".utf8) + be16(8)
        gsub += be16(0) + be16(1) + be16(0)
        gsub += be16(1) + be16(4)
        gsub += be16(3) + be16(0) + be16(1) + be16(8) // lookup: type 3, flag, subtableCount, offset
        gsub += be16(1) + be16(8) + be16(1) + be16(14) // AlternateSubst f1: format, coverage, altSetCount, setOffset
        gsub += be16(1) + be16(1) + be16(1) // coverage f1: glyph 1
        gsub += be16(2) + be16(7) + be16(8) // alternateSet: glyphCount 2, alternates 7, 8
        return assemble(extra: ("GSUB", gsub))
    }
}

/// A minimal TrueType font whose GSUB carries a populated ScriptList, for testing
/// feature selection (there are no lookups; the FeatureList and LookupList are
/// empty stubs, since the resolver returns feature *indices*). Two scripts:
///
///   - `DFLT`: a default language system listing feature index 0.
///   - `latn`: a default language system listing indices 0 and 1, and a named
///     `TRK ` language system with required feature 2 and listed index 0.
///
/// All offsets are relative to the GSUB table start (byte map in comments).
private enum LangSysFont {
    static func build() -> [UInt8] {
        // GSUB byte map (offsets relative to the table start):
        //   0  header (10)        scriptList 10, featureList 64, lookupList 66
        //   10 ScriptList (14)    DFLT -> Script +14 (->24), latn -> Script +26 (->36)
        //   24 DFLT Script (12)   defaultLangSys +4 (->28), langSysCount 0
        //   28 DFLT default (8)   required 0xFFFF, features [0]
        //   36 latn Script (10)   defaultLangSys +10 (->46), 1 record TRK -> +20 (->56)
        //   46 latn default (10)  required 0xFFFF, features [0, 1]
        //   56 TRK LangSys (8)    required 2, features [0]
        //   64 FeatureList (2)    featureCount 0
        //   66 LookupList (2)     lookupCount 0
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(64) + be16(66)
        gsub += be16(2) // ScriptList: scriptCount
        gsub += Array("DFLT".utf8) + be16(14) // ScriptRecord: DFLT -> Script at +14
        gsub += Array("latn".utf8) + be16(26) // ScriptRecord: latn -> Script at +26
        gsub += be16(4) + be16(0) // DFLT Script: defaultLangSysOffset 4, langSysCount 0
        gsub += be16(0) + be16(0xFFFF) + be16(1) + be16(0) // DFLT default LangSys: required none, features [0]
        gsub += be16(10) + be16(1) + Array("TRK ".utf8) + be16(20) // latn Script: defaultLangSys +10, TRK record -> +20
        gsub += be16(0) + be16(0xFFFF) + be16(2) + be16(0) + be16(1) // latn default LangSys: required none, features [0, 1]
        gsub += be16(0) + be16(2) + be16(1) + be16(0) // TRK LangSys: required 2, features [0]
        gsub += be16(0) // FeatureList: featureCount 0
        gsub += be16(0) // LookupList: lookupCount 0
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

/// A minimal TrueType font with a GPOS `mark` feature whose type-5 lookup is a
/// MarkLigPos subtable: mark glyph 3 (class 0, anchor 100,200) attaches to ligature
/// glyph 4, whose two components anchor class 0 at (300,500) and (400,600).
private enum MarkLigatureFont {
    static func build() -> [UInt8] {
        // GPOS layout (offsets relative to the table start):
        //   0  header(10)        scriptList 10, featureList 12, lookupList 26
        //   26 lookupList(6)     lookup type 5, subtable at +8 (->38)
        //   38 MarkLigPos(12)    markCov +12, ligCov +18, markClassCount 1,
        //                        markArray +24, ligatureArray +36
        //   50 markCoverage      glyph 3
        //   56 ligatureCoverage  glyph 4
        //   62 markArray         count 1, class 0, anchor +6; anchor 100,200
        //   74 ligatureArray     count 1, ligatureAttach +4
        //   78 LigatureAttach    componentCount 2, comp0 anchor +6, comp1 anchor +12
        //   84 component 0 anchor 300,500
        //   90 component 1 anchor 400,600
        var gpos: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gpos += be16(0)
        gpos += be16(1) + Array("mark".utf8) + be16(8)
        gpos += be16(0) + be16(1) + be16(0)
        gpos += be16(1) + be16(4)
        gpos += be16(5) + be16(0) + be16(1) + be16(8) // lookup: type 5
        gpos += be16(1) + be16(12) + be16(18) + be16(1) + be16(24) + be16(36) // MarkLigPos header
        gpos += be16(1) + be16(1) + be16(3) // markCoverage: glyph 3
        gpos += be16(1) + be16(1) + be16(4) // ligatureCoverage: glyph 4
        gpos += be16(1) + be16(0) + be16(6) // markArray: count, class 0, anchorOffset 6
        gpos += be16(1) + be16(100) + be16(200) // mark anchor (format 1)
        gpos += be16(1) + be16(4) // ligatureArray: ligatureCount 1, ligatureAttach +4
        gpos += be16(2) + be16(6) + be16(12) // LigatureAttach: componentCount 2, comp0 anchor +6, comp1 anchor +12
        gpos += be16(1) + be16(300) + be16(500) // component 0 anchor
        gpos += be16(1) + be16(400) + be16(600) // component 1 anchor
        return assemble(extra: ("GPOS", gpos))
    }
}

/// A minimal TrueType font with a GPOS `kern` feature whose type-8 lookup is a
/// ChainedSequenceContextFormat3 subtable: glyph 2, when preceded by glyph 1, is
/// adjusted by a nested type-1 single positioning (xAdvance -40). The positioning
/// analogue of ChainContextFont.
private enum ContextPosFont {
    static func build() -> [UInt8] {
        // GPOS byte map (offsets relative to the table start):
        //   0  header(10)        scriptList 10, featureList 12, lookupList 26
        //   12 featureList(14)   'kern' -> feature +8 (->20), lookup index 0
        //   26 lookupList(6)     lookup 0 (chained ctx) +6 (->32), lookup 1 (single) +44 (->70)
        //   32 lookup 0          type 8, subtable +8 (->40)
        //   40 chained ctx f3    backtrack cov +18 (->58), input cov +24 (->64), record (seq 0, lookup 1)
        //   58 backtrack cov     glyph 1
        //   64 input cov         glyph 2
        //   70 lookup 1          type 1, subtable +8 (->78)
        //   78 SinglePos f1      coverage +8 (->86), valueFormat 0x0004, xAdvance -40
        //   86 single cov        glyph 2
        var gpos: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gpos += be16(0) // scriptList
        gpos += be16(1) + Array("kern".utf8) + be16(8) // featureList: 'kern' -> feature +8
        gpos += be16(0) + be16(1) + be16(0) // feature: lookup 0
        gpos += be16(2) + be16(6) + be16(44) // lookupList: 2 lookups
        gpos += be16(8) + be16(0) + be16(1) + be16(8) // lookup 0: type 8, flag, subtable +8
        gpos += be16(3) + be16(1) + be16(18) + be16(1) + be16(24) + be16(0) + be16(1) + be16(0) + be16(1) // chained ctx f3
        gpos += be16(1) + be16(1) + be16(1) // backtrack coverage: glyph 1
        gpos += be16(1) + be16(1) + be16(2) // input coverage: glyph 2
        gpos += be16(1) + be16(0) + be16(1) + be16(8) // lookup 1: type 1, subtable +8
        gpos += be16(1) + be16(8) + be16(0x0004) + be16(0xFFD8) // SinglePos f1: coverage +8, valueFormat xAdvance, -40
        gpos += be16(1) + be16(1) + be16(2) // single positioning coverage: glyph 2
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

/// A minimal TrueType font with a GPOS `kern` feature whose type-1 lookup is a
/// SinglePosFormat1 subtable: glyph 1 takes xPlacement 30 and xAdvance -20 font
/// units (valueFormat 0x0005 = xPlacement + xAdvance).
private enum SinglePosFont1 {
    static func build() -> [UInt8] {
        // GPOS byte map (offsets relative to the table start):
        //   0  header(10)        scriptList 10, featureList 12, lookupList 26
        //   12 featureList(14)   'kern' -> feature +8 (->20), lookup index 0
        //   26 lookupList(6)     lookup 0 at +4 (->30)
        //   30 lookup 0          type 1, subtable +8 (->38)
        //   38 SinglePos f1      coverage +10 (->48), valueFormat 0x0005, value record
        //   44 value record      xPlacement 30, xAdvance -20
        //   48 coverage          glyph 1
        var gpos: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gpos += be16(0)
        gpos += be16(1) + Array("kern".utf8) + be16(8)
        gpos += be16(0) + be16(1) + be16(0)
        gpos += be16(1) + be16(4)
        gpos += be16(1) + be16(0) + be16(1) + be16(8) // lookup 0: type 1
        gpos += be16(1) + be16(10) + be16(0x0005) // SinglePos f1: format, coverage +10, valueFormat
        gpos += be16(30) + be16(0xFFEC) // value record: xPlacement 30, xAdvance -20
        gpos += be16(1) + be16(1) + be16(1) // coverage f1: glyph 1
        return assemble(extra: ("GPOS", gpos))
    }
}

/// A minimal TrueType font with a GPOS `kern` feature whose type-1 lookup is a
/// SinglePosFormat2 subtable: glyph 1 takes xAdvance +10, glyph 2 takes -10
/// (valueFormat 0x0004 = xAdvance only).
private enum SinglePosFont2 {
    static func build() -> [UInt8] {
        // GPOS byte map (offsets relative to the table start):
        //   38 SinglePos f2      coverage +12 (->50), valueFormat 0x0004, valueCount 2
        //   46 value records     glyph idx 0 xAdvance 10, idx 1 xAdvance -10
        //   50 coverage          glyph 1, glyph 2
        var gpos: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gpos += be16(0)
        gpos += be16(1) + Array("kern".utf8) + be16(8)
        gpos += be16(0) + be16(1) + be16(0)
        gpos += be16(1) + be16(4)
        gpos += be16(1) + be16(0) + be16(1) + be16(8) // lookup 0: type 1
        gpos += be16(2) + be16(12) + be16(0x0004) + be16(2) // SinglePos f2: format, coverage +12, valueFormat, valueCount
        gpos += be16(10) + be16(0xFFF6) // value records: xAdvance 10, xAdvance -10
        gpos += be16(1) + be16(2) + be16(1) + be16(2) // coverage f1: glyph 1, glyph 2
        return assemble(extra: ("GPOS", gpos))
    }
}

/// A minimal TrueType font with a GSUB `calt` feature whose type-5 lookup is a
/// ContextSubstFormat3 subtable: the input sequence (glyph 1, glyph 2) substitutes
/// glyph 2 (at sequence index 1) to glyph 9 through a nested type-1 lookup, with no
/// backtrack or lookahead. The sibling of ChainContextFont without the context.
private enum ContextFont {
    static func build() -> [UInt8] {
        // GSUB byte map (offsets relative to the table start):
        //   0  header(10)        scriptList 10, featureList 12, lookupList 26
        //   12 featureList(14)   'calt' -> feature +8 (->20), lookup index 0
        //   26 lookupList(6)     lookup 0 (context) +6 (->32), lookup 1 (single) +40 (->66)
        //   32 lookup 0          type 5, subtable +8 (->40)
        //   40 context subtable  format 3, glyphCount 2, seqLookupCount 1
        //   54 input cov 0       glyph 1
        //   60 input cov 1       glyph 2
        //   66 lookup 1          type 1, subtable +8 (->74)
        //   74 single subst      format 2, coverage +8, substitute glyph 9
        //   82 single cov        glyph 2
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gsub += be16(0) // scriptList
        gsub += be16(1) + Array("calt".utf8) + be16(8) // featureList: 'calt' -> feature at +8
        gsub += be16(0) + be16(1) + be16(0) // feature: lookupIndex 0
        gsub += be16(2) + be16(6) + be16(40) // lookupList: lookup 0 +6, lookup 1 +40
        gsub += be16(5) + be16(0) + be16(1) + be16(8) // lookup 0: type 5, flag, subtable +8
        gsub += be16(3) + be16(2) + be16(1) // context fmt3: format, glyphCount 2, seqLookupCount 1
        gsub += be16(14) + be16(20) // input coverage offsets: +14, +20
        gsub += be16(1) + be16(1) // record: sequenceIndex 1, lookupIndex 1
        gsub += be16(1) + be16(1) + be16(1) // input cov 0: glyph 1
        gsub += be16(1) + be16(1) + be16(2) // input cov 1: glyph 2
        gsub += be16(1) + be16(0) + be16(1) + be16(8) // lookup 1: type 1, subtable +8
        gsub += be16(2) + be16(8) + be16(1) + be16(9) // single subst format 2 -> glyph 9
        gsub += be16(1) + be16(1) + be16(2) // single subst coverage: glyph 2
        return assemble(extra: ("GSUB", gsub))
    }
}

/// A minimal TrueType font with a GSUB `calt` feature whose type-8 lookup is a
/// ReverseChainSingleSubstFormat1 subtable: glyph 2 is substituted by glyph 9 when
/// preceded by glyph 1 (one backtrack coverage, no lookahead).
private enum ReverseChainFont {
    static func build() -> [UInt8] {
        // GSUB byte map (offsets relative to the table start):
        //   0  header(10)        scriptList 10, featureList 12, lookupList 26
        //   12 featureList(14)   'calt' -> feature +8 (->20), lookup index 0
        //   26 lookupList(6)     lookup 0 +4 (->30)
        //   30 lookup 0          type 8, subtable +8 (->38)
        //   38 ReverseChainSubst input cov +14 (->52), 1 backtrack cov +20 (->58),
        //                        0 lookahead, substitute glyph 9
        //   52 input coverage    glyph 2
        //   58 backtrack cov     glyph 1
        var gsub: [UInt8] = be16(1) + be16(0) + be16(10) + be16(12) + be16(26)
        gsub += be16(0)
        gsub += be16(1) + Array("calt".utf8) + be16(8)
        gsub += be16(0) + be16(1) + be16(0)
        gsub += be16(1) + be16(4)
        gsub += be16(8) + be16(0) + be16(1) + be16(8) // lookup 0: type 8, flag, subCount, +8
        // ReverseChainSubst f1: format, coverage +14, backtrackCount 1, backtrack
        // cov +20, lookaheadCount 0, glyphCount 1, substitute glyph 9.
        gsub += be16(1) + be16(14) + be16(1) + be16(20) + be16(0) + be16(1) + be16(9)
        gsub += be16(1) + be16(1) + be16(2) // input coverage: glyph 2
        gsub += be16(1) + be16(1) + be16(1) // backtrack coverage: glyph 1
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
