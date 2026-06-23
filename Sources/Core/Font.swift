//
//  Font.swift
//  PureDraw
//

import Geometry
import Validation

/// A parsed TrueType or OpenType font (`.ttf`/`.otf`, or the first face of a `.ttc`
/// collection). Decodes `cmap` for character-to-glyph mapping and outlines from `glyf`
/// (quadratic), `CFF ` (Type 2), or `CFF2` (the variable-font Type 2 form), returned as
/// `Path` values in font units with y pointing up.
public struct Font: Equatable, Sendable {
    /// Font units per em square; glyph coordinates divide by this.
    public let unitsPerEm: Int
    /// Typographic ascent in font units.
    public let ascent: Double
    /// Typographic descent in font units (typically negative).
    public let descent: Double
    /// The number of glyphs in the font, the valid range for a glyph index.
    public let numberOfGlyphs: Int

    /// The raw sfnt bytes the font was parsed from, for embedding in formats
    /// such as PDF.
    public var sfntData: [UInt8] {
        data
    }

    private let data: [UInt8]
    private let tables: [String: (offset: Int, length: Int)]
    private let indexToLocFormat: Int
    private let numberOfHMetrics: Int
    private let cff: CFFFont?
    private let cff2: CFF2Font?

    /// Equality compares the underlying font data; every parsed field is
    /// derived from it.
    public static func == (lhs: Font, rhs: Font) -> Bool {
        lhs.data == rhs.data
    }

    // MARK: - Parsing

    /// Parses a font from a data provider, throwing a `ValidationError` if the sfnt is unreadable.
    public init(provider: DataProvider) throws {
        try self.init(data: provider.data())
    }

    /// Parses a font from raw sfnt bytes (`.ttf`/`.otf`, or the first face of a `.ttc`). Throws a
    /// `ValidationError` describing the first malformed or missing required table.
    public init(data bytes: [UInt8]) throws {
        var fontStart = 0
        if Self.tag(bytes, at: 0) == "ttcf" {
            guard let firstOffset = Self.u32(bytes, at: 12) else {
                throw Self.error("TrueType collection header is truncated")
            }
            fontStart = firstOffset
        }

        guard let version = Self.u32(bytes, at: fontStart) else {
            throw Self.error("font data is too short")
        }
        let isOpenTypeCFF = Self.tag(bytes, at: fontStart) == "OTTO"
        guard version == 0x0001_0000 || isOpenTypeCFF || Self.tag(bytes, at: fontStart) == "true" else {
            throw Self.error("not an sfnt font (bad version)")
        }

        guard let tableCount = Self.u16(bytes, at: fontStart + 4) else {
            throw Self.error("font directory is truncated")
        }
        var tableDirectory: [String: (offset: Int, length: Int)] = [:]
        for index in 0 ..< tableCount {
            let recordOffset = fontStart + 12 + index * 16
            guard let tableTag = Self.tag(bytes, at: recordOffset),
                  let offset = Self.u32(bytes, at: recordOffset + 8),
                  let length = Self.u32(bytes, at: recordOffset + 12),
                  offset + length <= bytes.count
            else {
                throw Self.error("font table directory entry \(index) is invalid")
            }
            tableDirectory[tableTag] = (offset: offset, length: length)
        }

        guard let head = tableDirectory["head"],
              let unitsPerEm = Self.u16(bytes, at: head.offset + 18),
              let locFormat = Self.u16(bytes, at: head.offset + 50)
        else {
            throw Self.error("missing or truncated head table")
        }
        guard unitsPerEm > 0 else {
            throw Self.error("invalid head table: unitsPerEm must be positive")
        }
        guard let maxp = tableDirectory["maxp"],
              let glyphCount = Self.u16(bytes, at: maxp.offset + 4)
        else {
            throw Self.error("missing or truncated maxp table")
        }
        guard let hhea = tableDirectory["hhea"],
              let ascender = Self.i16(bytes, at: hhea.offset + 4),
              let descender = Self.i16(bytes, at: hhea.offset + 6),
              let hMetricCount = Self.u16(bytes, at: hhea.offset + 34)
        else {
            throw Self.error("missing or truncated hhea table")
        }
        guard tableDirectory["cmap"] != nil else {
            throw Self.error("missing cmap table")
        }

        // Outlines come from glyf/loca (TrueType), a CFF table (PostScript-outlined
        // OpenType), or a CFF2 table (the variable-font PostScript form).
        var parsedCFF: CFFFont?
        var parsedCFF2: CFF2Font?
        if let cffTable = tableDirectory["CFF "] {
            parsedCFF = CFFFont(data: bytes, offset: cffTable.offset, length: cffTable.length)
            guard parsedCFF != nil else {
                throw Self.error("invalid CFF table")
            }
        } else if let cff2Table = tableDirectory["CFF2"] {
            parsedCFF2 = CFF2Font(data: bytes, offset: cff2Table.offset, length: cff2Table.length)
            guard parsedCFF2 != nil else {
                throw Self.error("invalid CFF2 table")
            }
        } else if tableDirectory["glyf"] == nil || tableDirectory["loca"] == nil {
            throw Self.error("missing glyf/loca or CFF outline tables")
        }

        data = bytes
        tables = tableDirectory
        self.unitsPerEm = unitsPerEm
        ascent = Double(ascender)
        descent = Double(descender)
        numberOfGlyphs = glyphCount
        indexToLocFormat = locFormat
        numberOfHMetrics = max(1, hMetricCount)
        cff = parsedCFF
        cff2 = parsedCFF2
    }

    private static func error(_ reason: String) -> ValidationError {
        ValidationError(reason: reason, at: [ValidationCodingKey("font")])
    }

    // MARK: - Character Mapping

    /// The glyph index for a Unicode scalar, or `nil` when unmapped.
    public func glyphIndex(for scalar: Unicode.Scalar) -> Int? {
        guard let cmap = tables["cmap"],
              let subtableCount = Self.u16(data, at: cmap.offset + 2)
        else { return nil }

        // Prefer a Unicode subtable: Windows/Unicode (3,10), (3,1), or platform 0.
        var bestOffset: Int?
        var bestScore = -1
        for index in 0 ..< subtableCount {
            let record = cmap.offset + 4 + index * 8
            guard let platform = Self.u16(data, at: record),
                  let encoding = Self.u16(data, at: record + 2),
                  let offset = Self.u32(data, at: record + 4)
            else { continue }
            let score = switch (platform, encoding) {
            case (3, 10): 4
            case (0, _): 3
            case (3, 1): 2
            default: 0
            }
            if score > bestScore {
                bestScore = score
                bestOffset = cmap.offset + offset
            }
        }
        guard let subtable = bestOffset, let format = Self.u16(data, at: subtable) else { return nil }

        let code = Int(scalar.value)
        switch format {
        case 0:
            guard code < 256, let glyph = Self.u8(data, at: subtable + 6 + code) else { return nil }
            return glyph == 0 ? nil : glyph

        case 4:
            return glyphIndexFormat4(subtable: subtable, code: code)

        case 6:
            guard let first = Self.u16(data, at: subtable + 6),
                  let count = Self.u16(data, at: subtable + 8),
                  code >= first, code < first + count,
                  let glyph = Self.u16(data, at: subtable + 10 + (code - first) * 2)
            else { return nil }
            return glyph == 0 ? nil : glyph

        case 12:
            guard let groupCount = Self.u32(data, at: subtable + 12) else { return nil }
            for group in 0 ..< groupCount {
                let groupOffset = subtable + 16 + group * 12
                guard let start = Self.u32(data, at: groupOffset),
                      let end = Self.u32(data, at: groupOffset + 4),
                      let startGlyph = Self.u32(data, at: groupOffset + 8)
                else { return nil }
                if code >= start, code <= end {
                    let glyph = startGlyph + (code - start)
                    return glyph == 0 ? nil : glyph
                }
            }
            return nil

        default:
            return nil
        }
    }

    private func glyphIndexFormat4(subtable: Int, code: Int) -> Int? {
        guard code <= 0xFFFF, let segCountX2 = Self.u16(data, at: subtable + 6) else { return nil }
        let segCount = segCountX2 / 2
        let endCodes = subtable + 14
        let startCodes = endCodes + segCountX2 + 2
        let idDeltas = startCodes + segCountX2
        let idRangeOffsets = idDeltas + segCountX2

        for segment in 0 ..< segCount {
            guard let end = Self.u16(data, at: endCodes + segment * 2), code <= end else { continue }
            guard let start = Self.u16(data, at: startCodes + segment * 2), code >= start else { return nil }
            guard let delta = Self.u16(data, at: idDeltas + segment * 2),
                  let rangeOffset = Self.u16(data, at: idRangeOffsets + segment * 2)
            else { return nil }

            let glyph: Int
            if rangeOffset == 0 {
                glyph = (code + delta) & 0xFFFF
            } else {
                let glyphAddress = idRangeOffsets + segment * 2 + rangeOffset + (code - start) * 2
                guard let indirect = Self.u16(data, at: glyphAddress), indirect != 0 else { return nil }
                glyph = (indirect + delta) & 0xFFFF
            }
            return glyph == 0 ? nil : glyph
        }
        return nil
    }

    // MARK: - Metrics

    /// The advance width for a glyph, in font units.
    public func advanceWidth(forGlyph index: Int) -> Double {
        guard let hmtx = tables["hmtx"], index >= 0 else { return 0 }
        let metricIndex = min(index, numberOfHMetrics - 1)
        guard let advance = Self.u16(data, at: hmtx.offset + metricIndex * 4) else { return 0 }
        return Double(advance)
    }

    // MARK: - Kerning

    /// The font's pairwise kerning, for the shaping tier to apply.
    ///
    /// It reads the OpenType `GPOS` pair-positioning lookups (the modern kerning
    /// source) for the `kern` feature, and falls back to the legacy TrueType
    /// `kern` table when a font carries no GPOS kerning. GPOS PairPos format 1
    /// (explicit pairs) is decoded here; PairPos format 2 (class-based pairs),
    /// the GSUB substitution lookups, and GDEF are the next slices of
    /// SlayerMotion/PureDraw#140.
    public func kerningMap() -> KerningMap {
        var pairs: [UInt64: Int] = [:]
        var classSubtables: [KerningClassSubtable] = []
        parseGPOSKern(into: &pairs, classSubtables: &classSubtables)
        if pairs.isEmpty, classSubtables.isEmpty {
            parseLegacyKern(into: &pairs)
        }
        return KerningMap(adjustments: pairs, classSubtables: classSubtables)
    }

    /// Reads GPOS `kern`-feature pair positioning (PairPos format 1) into `pairs`.
    ///
    /// Simplification (disclosed): the `kern` feature's lookups are gathered from
    /// the FeatureList directly, without per-script or per-language selection,
    /// which matches the common single-`kern`-feature font. Extension lookups
    /// (type 9) wrapping pair positioning are resolved.
    private func parseGPOSKern(into pairs: inout [UInt64: Int], classSubtables: inout [KerningClassSubtable]) {
        guard let gpos = tables["GPOS"] else { return }
        let base = gpos.offset
        guard let featureListOffset = Self.u16(data, at: base + 6),
              let lookupListOffset = Self.u16(data, at: base + 8)
        else {
            return
        }
        let featureList = base + featureListOffset
        let lookupList = base + lookupListOffset

        var kernLookupIndices: Set<Int> = []
        if let featureCount = Self.u16(data, at: featureList) {
            for featureIndex in 0 ..< featureCount {
                let record = featureList + 2 + featureIndex * 6
                guard Self.tag(data, at: record) == "kern",
                      let featureOffset = Self.u16(data, at: record + 4)
                else {
                    continue
                }
                let feature = featureList + featureOffset
                guard let lookupIndexCount = Self.u16(data, at: feature + 2) else { continue }
                for lookupIndex in 0 ..< lookupIndexCount {
                    if let index = Self.u16(data, at: feature + 4 + lookupIndex * 2) {
                        kernLookupIndices.insert(index)
                    }
                }
            }
        }

        guard let lookupCount = Self.u16(data, at: lookupList) else { return }
        for index in kernLookupIndices where index < lookupCount {
            guard let lookupOffset = Self.u16(data, at: lookupList + 2 + index * 2) else { continue }
            let lookup = lookupList + lookupOffset
            guard let lookupType = Self.u16(data, at: lookup),
                  let subtableCount = Self.u16(data, at: lookup + 4)
            else {
                continue
            }
            for subtableIndex in 0 ..< subtableCount {
                guard let subtableOffset = Self.u16(data, at: lookup + 6 + subtableIndex * 2) else { continue }
                var subtable = lookup + subtableOffset
                var effectiveType = lookupType
                if lookupType == 9 {
                    guard Self.u16(data, at: subtable) == 1,
                          let extensionType = Self.u16(data, at: subtable + 2),
                          let extensionOffset = Self.u32(data, at: subtable + 4)
                    else {
                        continue
                    }
                    effectiveType = extensionType
                    subtable += extensionOffset
                }
                if effectiveType == 2 {
                    guard let posFormat = Self.u16(data, at: subtable) else { continue }
                    if posFormat == 1 {
                        parsePairPosFormat1(subtable: subtable, into: &pairs)
                    } else if posFormat == 2 {
                        parsePairPosFormat2(subtable: subtable, into: &classSubtables)
                    }
                }
            }
        }
    }

    /// Decodes a GPOS PairPos format 2 (class-based pair) subtable into a
    /// ``KerningClassSubtable``, reusing the Coverage and ClassDef parsers.
    private func parsePairPosFormat2(subtable: Int, into classSubtables: inout [KerningClassSubtable]) {
        guard let coverageOffset = Self.u16(data, at: subtable + 2),
              let valueFormat1 = Self.u16(data, at: subtable + 4),
              let valueFormat2 = Self.u16(data, at: subtable + 6),
              let classDef1Offset = Self.u16(data, at: subtable + 8),
              let classDef2Offset = Self.u16(data, at: subtable + 10),
              let class1Count = Self.u16(data, at: subtable + 12),
              let class2Count = Self.u16(data, at: subtable + 14),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset),
              let classDef1 = OpenTypeClassDef(data: data, offset: subtable + classDef1Offset),
              let classDef2 = OpenTypeClassDef(data: data, offset: subtable + classDef2Offset)
        else {
            return
        }
        guard valueFormat1 & 0x0004 != 0, class1Count > 0, class2Count > 0 else { return }
        let value1Size = (valueFormat1 & 0xFF).nonzeroBitCount * 2
        let value2Size = (valueFormat2 & 0xFF).nonzeroBitCount * 2
        let recordSize = value1Size + value2Size
        let xAdvanceOffset = (valueFormat1 & 0x0003).nonzeroBitCount * 2
        let matrixBase = subtable + 16
        var xAdvances = [Int](repeating: 0, count: class1Count * class2Count)
        for firstClass in 0 ..< class1Count {
            for secondClass in 0 ..< class2Count {
                let cell = firstClass * class2Count + secondClass
                let record = matrixBase + cell * recordSize
                if let xAdvance = Self.i16(data, at: record + xAdvanceOffset) {
                    xAdvances[cell] = xAdvance
                }
            }
        }
        classSubtables.append(
            KerningClassSubtable(
                coveredFirstGlyphs: coverage.coveredGlyphs,
                firstClasses: classDef1.assignments,
                secondClasses: classDef2.assignments,
                secondClassCount: class2Count,
                xAdvances: xAdvances
            )
        )
    }

    /// Decodes a GPOS PairPos format 1 (explicit pair) subtable into `pairs`,
    /// extracting the first value record's x advance as the kerning amount.
    private func parsePairPosFormat1(subtable: Int, into pairs: inout [UInt64: Int]) {
        guard Self.u16(data, at: subtable) == 1,
              let coverageOffset = Self.u16(data, at: subtable + 2),
              let valueFormat1 = Self.u16(data, at: subtable + 4),
              let valueFormat2 = Self.u16(data, at: subtable + 6),
              let pairSetCount = Self.u16(data, at: subtable + 8),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
        else {
            return
        }
        guard valueFormat1 & 0x0004 != 0 else { return } // no x advance to read
        let value1Size = (valueFormat1 & 0xFF).nonzeroBitCount * 2
        let value2Size = (valueFormat2 & 0xFF).nonzeroBitCount * 2
        let xAdvanceOffset = (valueFormat1 & 0x0003).nonzeroBitCount * 2
        let recordSize = 2 + value1Size + value2Size
        for pairSetIndex in 0 ..< pairSetCount {
            guard let firstGlyph = coverage.glyph(atIndex: pairSetIndex),
                  let pairSetOffset = Self.u16(data, at: subtable + 10 + pairSetIndex * 2)
            else {
                continue
            }
            let pairSet = subtable + pairSetOffset
            guard let pairValueCount = Self.u16(data, at: pairSet) else { continue }
            for pairIndex in 0 ..< pairValueCount {
                let record = pairSet + 2 + pairIndex * recordSize
                guard let secondGlyph = Self.u16(data, at: record),
                      let xAdvance = Self.i16(data, at: record + 2 + xAdvanceOffset)
                else {
                    break
                }
                if xAdvance != 0 {
                    pairs[KerningMap.key(firstGlyph: firstGlyph, secondGlyph: secondGlyph)] = xAdvance
                }
            }
        }
    }

    /// Reads the legacy `kern` table (Microsoft format 0) into `pairs`.
    private func parseLegacyKern(into pairs: inout [UInt64: Int]) {
        guard let kern = tables["kern"],
              Self.u16(data, at: kern.offset) == 0,
              let subtableCount = Self.u16(data, at: kern.offset + 2)
        else {
            return
        }
        var subtableOffset = kern.offset + 4
        for _ in 0 ..< subtableCount {
            guard let length = Self.u16(data, at: subtableOffset + 2),
                  let coverage = Self.u16(data, at: subtableOffset + 4),
                  length > 0
            else {
                return
            }
            let format = (coverage >> 8) & 0xFF
            let isHorizontal = (coverage & 0x0001) != 0
            if format == 0, isHorizontal, let pairCount = Self.u16(data, at: subtableOffset + 6) {
                let pairsStart = subtableOffset + 14 // header(6) + nPairs/searchRange/entrySelector/rangeShift(8)
                for pairIndex in 0 ..< pairCount {
                    let record = pairsStart + pairIndex * 6
                    guard let left = Self.u16(data, at: record),
                          let right = Self.u16(data, at: record + 2),
                          let value = Self.i16(data, at: record + 4)
                    else {
                        break
                    }
                    pairs[KerningMap.key(firstGlyph: left, secondGlyph: right)] = value
                }
            }
            subtableOffset += length
        }
    }

    // MARK: - Substitution

    /// The font's `liga` ligature substitution rules, for the shaping tier to
    /// apply (for example `f` `i` becoming the `fi` ligature).
    ///
    /// This reads GSUB ligature substitution (lookup type 4) under the `liga`
    /// (standard) and `rlig` (required, the Arabic lam-alef) features, resolving
    /// extension lookups (type 7). Single substitution (type 1) is
    /// ``singleSubstitutions(feature:)``; the contextual lookups are the next
    /// slices of SlayerMotion/PureDraw#140.
    public func ligatures() -> [LigatureSubstitution] {
        var result: [LigatureSubstitution] = []
        parseGSUBLigatures(into: &result)
        return result
    }

    private func parseGSUBLigatures(into result: inout [LigatureSubstitution]) {
        guard let gsub = tables["GSUB"] else { return }
        let base = gsub.offset
        guard let featureListOffset = Self.u16(data, at: base + 6),
              let lookupListOffset = Self.u16(data, at: base + 8)
        else {
            return
        }
        let featureList = base + featureListOffset
        let lookupList = base + lookupListOffset

        var ligatureLookupIndices: Set<Int> = []
        if let featureCount = Self.u16(data, at: featureList) {
            for featureIndex in 0 ..< featureCount {
                let record = featureList + 2 + featureIndex * 6
                let tag = Self.tag(data, at: record)
                // `liga` is the standard Latin ligatures; `rlig` is required
                // ligatures, used for the Arabic lam-alef among others.
                guard tag == "liga" || tag == "rlig",
                      let featureOffset = Self.u16(data, at: record + 4)
                else {
                    continue
                }
                let feature = featureList + featureOffset
                guard let lookupIndexCount = Self.u16(data, at: feature + 2) else { continue }
                for lookupIndex in 0 ..< lookupIndexCount {
                    if let index = Self.u16(data, at: feature + 4 + lookupIndex * 2) {
                        ligatureLookupIndices.insert(index)
                    }
                }
            }
        }

        guard let lookupCount = Self.u16(data, at: lookupList) else { return }
        for index in ligatureLookupIndices where index < lookupCount {
            guard let lookupOffset = Self.u16(data, at: lookupList + 2 + index * 2) else { continue }
            let lookup = lookupList + lookupOffset
            guard let lookupType = Self.u16(data, at: lookup),
                  let subtableCount = Self.u16(data, at: lookup + 4)
            else {
                continue
            }
            for subtableIndex in 0 ..< subtableCount {
                guard let subtableOffset = Self.u16(data, at: lookup + 6 + subtableIndex * 2) else { continue }
                var subtable = lookup + subtableOffset
                var effectiveType = lookupType
                if lookupType == 7 {
                    guard Self.u16(data, at: subtable) == 1,
                          let extensionType = Self.u16(data, at: subtable + 2),
                          let extensionOffset = Self.u32(data, at: subtable + 4)
                    else {
                        continue
                    }
                    effectiveType = extensionType
                    subtable += extensionOffset
                }
                if effectiveType == 4 {
                    parseLigatureSubst(subtable: subtable, into: &result)
                }
            }
        }
    }

    /// Decodes a GSUB ligature substitution (type 4) subtable into `result`.
    private func parseLigatureSubst(subtable: Int, into result: inout [LigatureSubstitution]) {
        guard Self.u16(data, at: subtable) == 1,
              let coverageOffset = Self.u16(data, at: subtable + 2),
              let ligatureSetCount = Self.u16(data, at: subtable + 4),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
        else {
            return
        }
        for ligatureSetIndex in 0 ..< ligatureSetCount {
            guard let firstGlyph = coverage.glyph(atIndex: ligatureSetIndex),
                  let ligatureSetOffset = Self.u16(data, at: subtable + 6 + ligatureSetIndex * 2)
            else {
                continue
            }
            let ligatureSet = subtable + ligatureSetOffset
            guard let ligatureCount = Self.u16(data, at: ligatureSet) else { continue }
            for ligatureIndex in 0 ..< ligatureCount {
                guard let ligatureOffset = Self.u16(data, at: ligatureSet + 2 + ligatureIndex * 2) else { continue }
                let ligature = ligatureSet + ligatureOffset
                guard let ligatureGlyph = Self.u16(data, at: ligature),
                      let componentCount = Self.u16(data, at: ligature + 2),
                      componentCount >= 2
                else {
                    continue
                }
                var components = [firstGlyph]
                var valid = true
                for componentIndex in 0 ..< (componentCount - 1) {
                    guard let component = Self.u16(data, at: ligature + 4 + componentIndex * 2) else {
                        valid = false
                        break
                    }
                    components.append(component)
                }
                if valid {
                    result.append(LigatureSubstitution(components: components, ligatureGlyph: ligatureGlyph))
                }
            }
        }
    }

    /// The font's single-substitution map (GSUB lookup type 1) for a feature tag,
    /// for example `init`, `medi`, `fina`, and `isol` for Arabic positional
    /// forms: each input glyph maps to its substitute glyph. Extension lookups
    /// (type 7) are resolved. The shaping tier selects a feature per character
    /// (from cursive joining) and applies the returned map.
    public func singleSubstitutions(feature: String) -> [Int: Int] {
        var result: [Int: Int] = [:]
        guard let gsub = tables["GSUB"] else { return result }
        let base = gsub.offset
        guard let featureListOffset = Self.u16(data, at: base + 6),
              let lookupListOffset = Self.u16(data, at: base + 8)
        else {
            return result
        }
        let featureList = base + featureListOffset
        let lookupList = base + lookupListOffset

        var lookupIndices: Set<Int> = []
        if let featureCount = Self.u16(data, at: featureList) {
            for featureIndex in 0 ..< featureCount {
                let record = featureList + 2 + featureIndex * 6
                guard Self.tag(data, at: record) == feature,
                      let featureOffset = Self.u16(data, at: record + 4)
                else {
                    continue
                }
                let featureTable = featureList + featureOffset
                guard let lookupIndexCount = Self.u16(data, at: featureTable + 2) else { continue }
                for lookupIndex in 0 ..< lookupIndexCount {
                    if let index = Self.u16(data, at: featureTable + 4 + lookupIndex * 2) {
                        lookupIndices.insert(index)
                    }
                }
            }
        }

        guard let lookupCount = Self.u16(data, at: lookupList) else { return result }
        for index in lookupIndices.sorted() where index < lookupCount {
            guard let lookupOffset = Self.u16(data, at: lookupList + 2 + index * 2) else { continue }
            let lookup = lookupList + lookupOffset
            guard let lookupType = Self.u16(data, at: lookup),
                  let subtableCount = Self.u16(data, at: lookup + 4)
            else {
                continue
            }
            for subtableIndex in 0 ..< subtableCount {
                guard let subtableOffset = Self.u16(data, at: lookup + 6 + subtableIndex * 2) else { continue }
                var subtable = lookup + subtableOffset
                var effectiveType = lookupType
                if lookupType == 7 {
                    guard Self.u16(data, at: subtable) == 1,
                          let extensionType = Self.u16(data, at: subtable + 2),
                          let extensionOffset = Self.u32(data, at: subtable + 4)
                    else {
                        continue
                    }
                    effectiveType = extensionType
                    subtable += extensionOffset
                }
                if effectiveType == 1 {
                    parseSingleSubst(subtable: subtable, into: &result)
                }
            }
        }
        return result
    }

    /// Decodes a GSUB single substitution (type 1) subtable into `result`.
    /// Format 1 adds a signed delta to each covered glyph; format 2 lists an
    /// explicit substitute per covered glyph in coverage order.
    private func parseSingleSubst(subtable: Int, into result: inout [Int: Int]) {
        guard let format = Self.u16(data, at: subtable),
              let coverageOffset = Self.u16(data, at: subtable + 2),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
        else {
            return
        }
        if format == 1 {
            guard let delta = Self.i16(data, at: subtable + 4) else { return }
            for glyph in coverage.coveredGlyphs {
                result[glyph] = (glyph + delta) & 0xFFFF
            }
        } else if format == 2 {
            guard let glyphCount = Self.u16(data, at: subtable + 4) else { return }
            for index in 0 ..< glyphCount {
                guard let glyph = coverage.glyph(atIndex: index),
                      let substitute = Self.u16(data, at: subtable + 6 + index * 2)
                else {
                    continue
                }
                result[glyph] = substitute
            }
        }
    }

    // MARK: - Outlines

    /// The glyph outline as a path in font units (y up), or `nil` for empty
    /// or out-of-range glyphs.
    public func outline(forGlyph index: Int) -> Path? {
        if let cff {
            return cff.outline(glyphIndex: index)
        }
        if let cff2 {
            return cff2.outline(glyphIndex: index)
        }
        return outline(forGlyph: index, depth: 0)
    }

    /// The embedded bitmap for `index`, if the font carries an Apple `sbix` table with a PNG
    /// strike for that glyph (PureDraw #80). Color/emoji fonts store glyphs as bitmaps here
    /// rather than as outlines; the first strike that has a PNG for the glyph is decoded (via
    /// the PNG decoder, #103). Returns nil for outline glyphs, empty strikes, or the
    /// non-PNG graphic types (`jpg `, `tiff`, `dupe`), which are not decoded.
    public func glyphBitmap(forGlyph index: Int) -> Image? {
        guard index >= 0, index < numberOfGlyphs, let sbix = tables["sbix"] else { return nil }
        let base = sbix.offset
        guard let numStrikes = Self.u32(data, at: base + 4), numStrikes > 0 else { return nil }
        for strike in 0 ..< numStrikes {
            guard let strikeOffset = Self.u32(data, at: base + 8 + strike * 4) else { continue }
            let strikeBase = base + strikeOffset
            // strike: ppem (2), ppi (2), then numGlyphs+1 u32 glyph-data offsets (from strikeBase).
            let offsetTable = strikeBase + 4
            guard let glyphOffset = Self.u32(data, at: offsetTable + index * 4),
                  let nextOffset = Self.u32(data, at: offsetTable + (index + 1) * 4),
                  nextOffset > glyphOffset // equal means no bitmap for this glyph in this strike
            else { continue }
            // glyph data: originOffsetX (2), originOffsetY (2), graphicType tag (4), image bytes.
            let glyphStart = strikeBase + glyphOffset
            guard let graphicType = Self.tag(data, at: glyphStart + 4) else { continue }
            let imageStart = glyphStart + 8, imageEnd = strikeBase + nextOffset
            guard graphicType == "png ", imageStart < imageEnd, imageEnd <= data.count else { continue }
            return try? ImageDecoder.decode(Array(data[imageStart ..< imageEnd]))
        }
        return nil
    }

    /// The color layers for `index`, if the font carries OpenType `COLR`/`CPAL` tables (version 0)
    /// with a color-glyph definition for it (PureDraw #79). A color glyph is drawn by filling each
    /// layer's outline (an ordinary glyph, via `outline(forGlyph:)`) with its palette color, in the
    /// returned back-to-front order. Palette 0 is used. Returns nil for non-color glyphs or when the
    /// tables are absent or not version 0. The 0xFFFF palette index (the text foreground) resolves to
    /// opaque black, the conventional default.
    public func colorLayers(forGlyph index: Int) -> [(glyph: Int, color: Color)]? {
        guard let colr = tables["COLR"], tables["CPAL"] != nil,
              Self.u16(data, at: colr.offset) == 0, // COLR version 0
              let numBase = Self.u16(data, at: colr.offset + 2),
              let baseOffset = Self.u32(data, at: colr.offset + 4),
              let layersOffset = Self.u32(data, at: colr.offset + 8),
              let numLayerRecords = Self.u16(data, at: colr.offset + 12)
        else { return nil }
        // Locate the base-glyph record for `index` (records are sorted by glyph id).
        var span: (first: Int, count: Int)?
        for record in 0 ..< numBase {
            let rec = colr.offset + baseOffset + record * 6
            guard let gid = Self.u16(data, at: rec) else { return nil }
            if gid == index {
                guard let first = Self.u16(data, at: rec + 2), let count = Self.u16(data, at: rec + 4) else { return nil }
                span = (first, count)
                break
            }
        }
        guard let span else { return nil }

        var layers: [(glyph: Int, color: Color)] = []
        for offset in 0 ..< span.count {
            let layerIndex = span.first + offset
            guard layerIndex < numLayerRecords else { return nil }
            let rec = colr.offset + layersOffset + layerIndex * 4
            guard let layerGlyph = Self.u16(data, at: rec),
                  let paletteIndex = Self.u16(data, at: rec + 2),
                  let color = paletteColor(paletteIndex: paletteIndex)
            else { return nil }
            layers.append((layerGlyph, color))
        }
        return layers
    }

    /// Resolves a CPAL color for `paletteIndex` in palette 0; 0xFFFF is the text foreground (black).
    private func paletteColor(paletteIndex: Int) -> Color? {
        if paletteIndex == 0xFFFF { return Color(red: 0, green: 0, blue: 0, alpha: 1) }
        guard let cpal = tables["CPAL"],
              let numPaletteEntries = Self.u16(data, at: cpal.offset + 2),
              paletteIndex < numPaletteEntries,
              let colorRecordsOffset = Self.u32(data, at: cpal.offset + 8),
              let firstRecord = Self.u16(data, at: cpal.offset + 12) // colorRecordIndices[0], palette 0
        else { return nil }
        let off = cpal.offset + colorRecordsOffset + (firstRecord + paletteIndex) * 4
        guard off + 4 <= data.count else { return nil }
        // CPAL color records are stored blue, green, red, alpha.
        return Color(
            red: Double(data[off + 2]) / 255,
            green: Double(data[off + 1]) / 255,
            blue: Double(data[off]) / 255,
            alpha: Double(data[off + 3]) / 255
        )
    }

    // MARK: - Variable Fonts

    /// Whether the font carries an `fvar` table, that is, whether it is an OpenType variable font.
    public var isVariable: Bool {
        tables["fvar"] != nil
    }

    /// The variation axes of a variable font, in `fvar` order (PureDraw #77). Empty for a static
    /// font or a malformed `fvar` table. Reading the axes does not change which instance the glyph
    /// outlines render at; outline interpolation (`gvar`) is a separate capability.
    public var variationAxes: [VariationAxis] {
        guard let fvar = tables["fvar"],
              let axesOffset = Self.u16(data, at: fvar.offset + 4),
              let axisCount = Self.u16(data, at: fvar.offset + 8),
              let axisSize = Self.u16(data, at: fvar.offset + 10), axisSize >= 20
        else { return [] }
        var axes: [VariationAxis] = []
        for index in 0 ..< axisCount {
            let record = fvar.offset + axesOffset + index * axisSize
            guard let tag = Self.tag(data, at: record),
                  let minValue = Self.fixed16(data, at: record + 4),
                  let defaultValue = Self.fixed16(data, at: record + 8),
                  let maxValue = Self.fixed16(data, at: record + 12),
                  let nameID = Self.u16(data, at: record + 18)
            else { return [] }
            axes.append(VariationAxis(tag: tag, minValue: minValue, defaultValue: defaultValue, maxValue: maxValue, nameID: nameID))
        }
        return axes
    }

    /// The named instances of a variable font, in `fvar` order (PureDraw #77). Each instance gives a
    /// user-space coordinate per axis, matching `variationAxes`. Empty for a static or malformed font.
    public var namedInstances: [VariationInstance] {
        guard let fvar = tables["fvar"],
              let axesOffset = Self.u16(data, at: fvar.offset + 4),
              let axisCount = Self.u16(data, at: fvar.offset + 8),
              let axisSize = Self.u16(data, at: fvar.offset + 10),
              let instanceCount = Self.u16(data, at: fvar.offset + 12),
              let instanceSize = Self.u16(data, at: fvar.offset + 14)
        else { return [] }
        // Instances follow the axes array; coordinates are one Fixed per axis after the 4-byte head.
        let instancesStart = fvar.offset + axesOffset + axisCount * axisSize
        let coordinateBytes = axisCount * 4
        guard instanceSize >= coordinateBytes + 4 else { return [] }
        let hasPostScriptName = instanceSize >= coordinateBytes + 6
        var instances: [VariationInstance] = []
        for index in 0 ..< instanceCount {
            let record = instancesStart + index * instanceSize
            guard let subfamilyNameID = Self.u16(data, at: record) else { return [] }
            var coordinates: [Double] = []
            for axis in 0 ..< axisCount {
                guard let value = Self.fixed16(data, at: record + 4 + axis * 4) else { return [] }
                coordinates.append(value)
            }
            let postScriptNameID: Int? = hasPostScriptName ? Self.u16(data, at: record + 4 + coordinateBytes) : nil
            instances.append(VariationInstance(subfamilyNameID: subfamilyNameID, coordinates: coordinates, postScriptNameID: postScriptNameID))
        }
        return instances
    }

    /// The outline of `index` interpolated to a variation instance, mapping axis tag to a
    /// user-space coordinate (axes you omit stay at their default value) (PureDraw #77). It applies
    /// `gvar` deltas to simple-glyph points and to composite-glyph component offsets, with coordinate
    /// normalization honoring `avar` when present, so the result matches the platform shaper. Falls
    /// back to the default outline when the font is static or the glyph carries no variation data.
    public func outline(forGlyph index: Int, variations: [String: Double]) -> Path? {
        guard tables["gvar"] != nil, let normalized = normalizedVariationCoordinates(variations) else {
            return outline(forGlyph: index)
        }
        return variedOutline(forGlyph: index, normalized: normalized, depth: 0) ?? outline(forGlyph: index)
    }

    private func variedOutline(forGlyph index: Int, normalized: [Double], depth: Int) -> Path? {
        guard depth < 6, let range = glyphRange(index), let contourCount = Self.i16(data, at: range.offset) else { return nil }
        if contourCount >= 0 {
            guard let glyph = simpleGlyphPoints(at: range.offset, contourCount: contourCount) else { return nil }
            guard let deltas = gvarDeltas(glyph: index, xs: glyph.xs, ys: glyph.ys, endPoints: glyph.endPoints, normalized: normalized) else {
                return buildSimplePath(xs: glyph.xs, ys: glyph.ys, flags: glyph.flags, endPoints: glyph.endPoints)
            }
            let xs = zip(glyph.xs, deltas.dx).map(+)
            let ys = zip(glyph.ys, deltas.dy).map(+)
            return buildSimplePath(xs: xs, ys: ys, flags: glyph.flags, endPoints: glyph.endPoints)
        }
        return variedCompositeOutline(at: range.offset, glyph: index, normalized: normalized, depth: depth)
    }

    /// A composite glyph at a variation instance: `gvar` supplies one delta per component that shifts
    /// its x/y offset (there is no contour interpolation for composites), and each component is itself
    /// interpolated. Point-matched components (not offset-based) cannot have their anchors varied, so
    /// such a glyph falls back to its default composite outline.
    private func variedCompositeOutline(at glyphOffset: Int, glyph index: Int, normalized: [Double], depth: Int) -> Path? {
        guard let components = compositeComponents(at: glyphOffset) else { return nil }
        guard components.allSatisfy(\.argsAreXY) else { return compositeOutline(at: glyphOffset, depth: depth) }
        let placeholder = [Double](repeating: 0, count: components.count)
        let deltas = gvarDeltas(glyph: index, xs: placeholder, ys: placeholder, endPoints: [], normalized: normalized) ?? (dx: placeholder, dy: placeholder)
        var path = Path()
        for (componentIndex, component) in components.enumerated() {
            guard let sub = variedOutline(forGlyph: component.glyphIndex, normalized: normalized, depth: depth + 1) else { continue }
            let ddx = componentIndex < deltas.dx.count ? deltas.dx[componentIndex] : 0
            let ddy = componentIndex < deltas.dy.count ? deltas.dy[componentIndex] : 0
            let transform = component.scale.concatenating(.translation(x: component.dx + ddx, y: component.dy + ddy))
            path.addPath(sub.applying(transform))
        }
        return path
    }

    /// Normalizes user-space variation values to the [-1, 1] axis space, applying `avar` if present.
    /// Returns nil when the font is static.
    private func normalizedVariationCoordinates(_ variations: [String: Double]) -> [Double]? {
        let axes = variationAxes
        guard !axes.isEmpty else { return nil }
        let coords = axes.map { axis -> Double in
            let value = min(max(variations[axis.tag] ?? axis.defaultValue, axis.minValue), axis.maxValue)
            if value < axis.defaultValue {
                return axis.defaultValue > axis.minValue ? -(axis.defaultValue - value) / (axis.defaultValue - axis.minValue) : 0
            } else if value > axis.defaultValue {
                return axis.maxValue > axis.defaultValue ? (value - axis.defaultValue) / (axis.maxValue - axis.defaultValue) : 0
            }
            return 0
        }
        return applyAvar(coords)
    }

    /// Remaps normalized coordinates through the `avar` segment maps, leaving them unchanged when the
    /// table is absent or its axis count disagrees.
    private func applyAvar(_ coords: [Double]) -> [Double] {
        guard let avar = tables["avar"],
              let axisCount = Self.u16(data, at: avar.offset + 6), axisCount == coords.count
        else { return coords }
        var cursor = avar.offset + 8
        var result = coords
        for axis in 0 ..< axisCount {
            guard let mapCount = Self.u16(data, at: cursor) else { return coords }
            cursor += 2
            var pairs: [(from: Double, to: Double)] = []
            for _ in 0 ..< mapCount {
                guard let from = Self.f2dot14(data, at: cursor), let to = Self.f2dot14(data, at: cursor + 2) else { return coords }
                pairs.append((from, to))
                cursor += 4
            }
            result[axis] = remapAvar(result[axis], pairs: pairs)
        }
        return result
    }

    private func remapAvar(_ value: Double, pairs: [(from: Double, to: Double)]) -> Double {
        guard pairs.count >= 2, let first = pairs.first, let last = pairs.last else { return value }
        if value <= first.from { return first.to }
        if value >= last.from { return last.to }
        for index in 1 ..< pairs.count {
            let lo = pairs[index - 1], hi = pairs[index]
            if value >= lo.from, value <= hi.from {
                guard hi.from > lo.from else { return lo.to }
                return lo.to + (value - lo.from) / (hi.from - lo.from) * (hi.to - lo.to)
            }
        }
        return value
    }

    /// Accumulates the `gvar` deltas for one glyph at `normalized`, returning per-point x/y offsets in
    /// font units. Returns nil when the glyph has no variation data (render it at the default).
    private func gvarDeltas(glyph: Int, xs: [Double], ys: [Double], endPoints: [Int], normalized: [Double]) -> (dx: [Double], dy: [Double])? {
        let pointCount = xs.count
        guard let gvar = tables["gvar"],
              let axisCount = Self.u16(data, at: gvar.offset + 4), axisCount == normalized.count,
              let sharedTupleCount = Self.u16(data, at: gvar.offset + 6),
              let sharedTuplesOffset = Self.u32(data, at: gvar.offset + 8),
              let glyphCount = Self.u16(data, at: gvar.offset + 12),
              let flags = Self.u16(data, at: gvar.offset + 14),
              let dataArrayOffset = Self.u32(data, at: gvar.offset + 16),
              glyph < glyphCount
        else { return nil }

        let longOffsets = flags & 0x0001 != 0
        let offsetsBase = gvar.offset + 20
        let dataStartRel: Int
        let dataEndRel: Int
        if longOffsets {
            guard let start = Self.u32(data, at: offsetsBase + glyph * 4),
                  let end = Self.u32(data, at: offsetsBase + (glyph + 1) * 4) else { return nil }
            (dataStartRel, dataEndRel) = (start, end)
        } else {
            guard let start = Self.u16(data, at: offsetsBase + glyph * 2),
                  let end = Self.u16(data, at: offsetsBase + (glyph + 1) * 2) else { return nil }
            (dataStartRel, dataEndRel) = (start * 2, end * 2)
        }
        guard dataEndRel > dataStartRel else { return nil } // no deltas for this glyph
        let glyphDataStart = gvar.offset + dataArrayOffset + dataStartRel

        guard let tupleCountRaw = Self.u16(data, at: glyphDataStart),
              let serializedOffset = Self.u16(data, at: glyphDataStart + 2) else { return nil }
        let tupleCount = tupleCountRaw & 0x0FFF
        let totalPoints = pointCount + 4 // 4 trailing phantom points
        var serializedCursor = glyphDataStart + serializedOffset

        var sharedPoints: [Int]?
        if tupleCountRaw & 0x8000 != 0 { // SHARED_POINT_NUMBERS
            guard let (points, consumed) = readPackedPointNumbers(at: serializedCursor, totalPoints: totalPoints) else { return nil }
            sharedPoints = points
            serializedCursor += consumed
        }

        var accDx = [Double](repeating: 0, count: pointCount)
        var accDy = [Double](repeating: 0, count: pointCount)
        var headerCursor = glyphDataStart + 4

        for _ in 0 ..< tupleCount {
            guard let variationDataSize = Self.u16(data, at: headerCursor),
                  let tupleIndex = Self.u16(data, at: headerCursor + 2) else { return nil }
            headerCursor += 4

            var peak = [Double](repeating: 0, count: axisCount)
            if tupleIndex & 0x8000 != 0 { // EMBEDDED_PEAK_TUPLE
                for axis in 0 ..< axisCount {
                    guard let value = Self.f2dot14(data, at: headerCursor) else { return nil }
                    peak[axis] = value
                    headerCursor += 2
                }
            } else {
                let sharedIndex = tupleIndex & 0x0FFF
                guard sharedIndex < sharedTupleCount else { return nil }
                let base = gvar.offset + sharedTuplesOffset + sharedIndex * axisCount * 2
                for axis in 0 ..< axisCount {
                    guard let value = Self.f2dot14(data, at: base + axis * 2) else { return nil }
                    peak[axis] = value
                }
            }

            var intermediateStart: [Double]?
            var intermediateEnd: [Double]?
            if tupleIndex & 0x4000 != 0 { // INTERMEDIATE_REGION
                var lower = [Double](repeating: 0, count: axisCount)
                var upper = [Double](repeating: 0, count: axisCount)
                for axis in 0 ..< axisCount {
                    guard let value = Self.f2dot14(data, at: headerCursor) else { return nil }
                    lower[axis] = value
                    headerCursor += 2
                }
                for axis in 0 ..< axisCount {
                    guard let value = Self.f2dot14(data, at: headerCursor) else { return nil }
                    upper[axis] = value
                    headerCursor += 2
                }
                intermediateStart = lower
                intermediateEnd = upper
            }

            let blockStart = serializedCursor
            serializedCursor += variationDataSize
            let scalar = tupleScalar(peak: peak, start: intermediateStart, end: intermediateEnd, normalized: normalized)
            if scalar == 0 { continue }

            var dataCursor = blockStart
            let pointSet: [Int]
            if tupleIndex & 0x2000 != 0 { // PRIVATE_POINT_NUMBERS
                guard let (points, consumed) = readPackedPointNumbers(at: dataCursor, totalPoints: totalPoints) else { return nil }
                pointSet = points
                dataCursor += consumed
            } else if let sharedPoints {
                pointSet = sharedPoints
            } else {
                pointSet = Array(0 ..< totalPoints)
            }

            guard let (dxDeltas, dxConsumed) = readPackedDeltas(at: dataCursor, count: pointSet.count) else { return nil }
            dataCursor += dxConsumed
            guard let (dyDeltas, _) = readPackedDeltas(at: dataCursor, count: pointSet.count) else { return nil }

            accumulateTupleDeltas(
                pointSet: pointSet, dx: dxDeltas, dy: dyDeltas, scalar: scalar,
                xs: xs, ys: ys, endPoints: endPoints, accDx: &accDx, accDy: &accDy
            )
        }
        return (accDx, accDy)
    }

    /// The interpolation scalar for one tuple at `normalized` (the canonical per-axis tent product:
    /// a peak of 0 leaves an axis out, a current coordinate of 0 against a nonzero peak zeroes the
    /// tuple, and intermediate regions use their explicit start/end bounds).
    private func tupleScalar(peak: [Double], start: [Double]?, end: [Double]?, normalized: [Double]) -> Double {
        var scalar = 1.0
        for axis in 0 ..< peak.count {
            let peakValue = peak[axis]
            let coordinate = normalized[axis]
            if peakValue == 0 { continue }
            if coordinate == 0 { return 0 }
            if coordinate == peakValue { continue }
            if let start, let end {
                let lower = start[axis], upper = end[axis]
                if coordinate < lower || coordinate > upper { return 0 }
                if coordinate < peakValue {
                    if peakValue != lower { scalar *= (coordinate - lower) / (peakValue - lower) }
                } else if upper != peakValue {
                    scalar *= (upper - coordinate) / (upper - peakValue)
                }
            } else {
                if coordinate < min(0, peakValue) || coordinate > max(0, peakValue) { return 0 }
                scalar *= coordinate / peakValue
            }
        }
        return scalar
    }

    /// Reads a packed point-number list (gvar/cvar). A leading count of 0 means "all points".
    private func readPackedPointNumbers(at offset: Int, totalPoints: Int) -> (points: [Int], consumed: Int)? {
        guard let first = Self.u8(data, at: offset) else { return nil }
        var cursor = offset + 1
        let count: Int
        if first & 0x80 != 0 {
            guard let second = Self.u8(data, at: cursor) else { return nil }
            count = ((first & 0x7F) << 8) | second
            cursor += 1
        } else {
            count = first
        }
        if count == 0 { return (Array(0 ..< totalPoints), cursor - offset) }

        var points: [Int] = []
        var value = 0
        while points.count < count {
            guard let control = Self.u8(data, at: cursor) else { return nil }
            cursor += 1
            let runCount = (control & 0x7F) + 1
            let wordSized = control & 0x80 != 0
            for _ in 0 ..< runCount where points.count < count {
                if wordSized {
                    guard let delta = Self.u16(data, at: cursor) else { return nil }
                    cursor += 2
                    value += delta
                } else {
                    guard let delta = Self.u8(data, at: cursor) else { return nil }
                    cursor += 1
                    value += delta
                }
                points.append(value)
            }
        }
        return (points, cursor - offset)
    }

    /// Reads a run-length-packed delta array of `count` signed values (gvar X then Y blocks).
    private func readPackedDeltas(at offset: Int, count: Int) -> (deltas: [Int], consumed: Int)? {
        var deltas: [Int] = []
        var cursor = offset
        while deltas.count < count {
            guard let control = Self.u8(data, at: cursor) else { return nil }
            cursor += 1
            let runCount = (control & 0x3F) + 1
            if control & 0x80 != 0 { // DELTAS_ARE_ZERO
                for _ in 0 ..< runCount where deltas.count < count {
                    deltas.append(0)
                }
            } else if control & 0x40 != 0 { // DELTAS_ARE_WORDS
                for _ in 0 ..< runCount where deltas.count < count {
                    guard let delta = Self.i16(data, at: cursor) else { return nil }
                    cursor += 2
                    deltas.append(delta)
                }
            } else {
                for _ in 0 ..< runCount where deltas.count < count {
                    guard let delta = Self.i8(data, at: cursor) else { return nil }
                    cursor += 1
                    deltas.append(delta)
                }
            }
        }
        return (deltas, cursor - offset)
    }

    /// Applies one tuple's deltas to the accumulators: explicit deltas on the touched points (phantom
    /// points, index >= pointCount, are dropped), then IUP-interpolated deltas on the untouched ones.
    private func accumulateTupleDeltas(
        pointSet: [Int], dx: [Int], dy: [Int], scalar: Double,
        xs: [Double], ys: [Double], endPoints: [Int],
        accDx: inout [Double], accDy: inout [Double]
    ) {
        let pointCount = xs.count
        var touched = [Bool](repeating: false, count: pointCount)
        var tdx = [Double](repeating: 0, count: pointCount)
        var tdy = [Double](repeating: 0, count: pointCount)
        for (index, point) in pointSet.enumerated() where point < pointCount && index < dx.count && index < dy.count {
            touched[point] = true
            tdx[point] = Double(dx[index])
            tdy[point] = Double(dy[index])
        }
        if touched.contains(false) {
            var start = 0
            for end in endPoints {
                if end >= start, end < pointCount {
                    let range = Array(start ... end)
                    iupContour(range: range, coords: xs, touched: touched, deltas: &tdx)
                    iupContour(range: range, coords: ys, touched: touched, deltas: &tdy)
                }
                start = end + 1
            }
        }
        for index in 0 ..< pointCount {
            accDx[index] += scalar * tdx[index]
            accDy[index] += scalar * tdy[index]
        }
    }

    /// Interpolates one contour's untouched-point deltas (IUP) for a single coordinate axis, using the
    /// touched points on either side along the contour as references.
    private func iupContour(range: [Int], coords: [Double], touched: [Bool], deltas: inout [Double]) {
        let count = range.count
        let touchedLocal = (0 ..< count).filter { touched[range[$0]] }
        guard !touchedLocal.isEmpty else { return } // no references: leave deltas at 0
        for slot in 0 ..< touchedLocal.count {
            let firstTouched = touchedLocal[slot]
            let nextTouched = touchedLocal[(slot + 1) % touchedLocal.count]
            var local = (firstTouched + 1) % count
            while local != nextTouched {
                let point = range[local]
                deltas[point] = iupValue(
                    coords[point],
                    reference1: coords[range[firstTouched]], delta1: deltas[range[firstTouched]],
                    reference2: coords[range[nextTouched]], delta2: deltas[range[nextTouched]]
                )
                local = (local + 1) % count
            }
        }
    }

    private func iupValue(_ coordinate: Double, reference1: Double, delta1: Double, reference2: Double, delta2: Double) -> Double {
        if reference1 == reference2 { return delta1 == delta2 ? delta1 : 0 }
        let lower = reference1 < reference2 ? (reference1, delta1) : (reference2, delta2)
        let upper = reference1 < reference2 ? (reference2, delta2) : (reference1, delta1)
        if coordinate <= lower.0 { return lower.1 }
        if coordinate >= upper.0 { return upper.1 }
        return lower.1 + (coordinate - lower.0) / (upper.0 - lower.0) * (upper.1 - lower.1)
    }

    private func glyphRange(_ index: Int) -> (offset: Int, length: Int)? {
        guard index >= 0, index < numberOfGlyphs,
              let loca = tables["loca"], let glyf = tables["glyf"]
        else { return nil }

        let start: Int
        let end: Int
        if indexToLocFormat == 0 {
            guard let rawStart = Self.u16(data, at: loca.offset + index * 2),
                  let rawEnd = Self.u16(data, at: loca.offset + (index + 1) * 2)
            else { return nil }
            start = rawStart * 2
            end = rawEnd * 2
        } else {
            guard let rawStart = Self.u32(data, at: loca.offset + index * 4),
                  let rawEnd = Self.u32(data, at: loca.offset + (index + 1) * 4)
            else { return nil }
            start = rawStart
            end = rawEnd
        }
        guard end > start, glyf.offset + end <= glyf.offset + glyf.length else { return nil }
        return (offset: glyf.offset + start, length: end - start)
    }

    private func outline(forGlyph index: Int, depth: Int) -> Path? {
        guard depth < 6, let range = glyphRange(index),
              let contourCount = Self.i16(data, at: range.offset)
        else { return nil }

        if contourCount >= 0 {
            return simpleOutline(at: range.offset, contourCount: contourCount)
        }
        return compositeOutline(at: range.offset, depth: depth)
    }

    private func simpleOutline(at glyphOffset: Int, contourCount: Int) -> Path? {
        guard let glyph = simpleGlyphPoints(at: glyphOffset, contourCount: contourCount) else { return nil }
        return buildSimplePath(xs: glyph.xs, ys: glyph.ys, flags: glyph.flags, endPoints: glyph.endPoints)
    }

    /// Decodes the raw on/off-curve points of a simple glyph (the form `gvar` deltas apply to,
    /// before the contour is reconstructed). `xs`/`ys` are in font units; `flags` bit 0 is on-curve.
    private func simpleGlyphPoints(at glyphOffset: Int, contourCount: Int) -> (xs: [Double], ys: [Double], flags: [Int], endPoints: [Int])? {
        var cursor = glyphOffset + 10
        var endPoints: [Int] = []
        for _ in 0 ..< contourCount {
            guard let endPoint = Self.u16(data, at: cursor) else { return nil }
            endPoints.append(endPoint)
            cursor += 2
        }
        guard let instructionLength = Self.u16(data, at: cursor) else { return nil }
        cursor += 2 + instructionLength
        let pointCount = (endPoints.last ?? -1) + 1
        guard pointCount > 0 else { return nil }

        // Flags, with repeat compression.
        var flags: [Int] = []
        while flags.count < pointCount {
            guard let flag = Self.u8(data, at: cursor) else { return nil }
            cursor += 1
            flags.append(flag)
            if flag & 0x08 != 0 { // REPEAT_FLAG
                guard let repeatCount = Self.u8(data, at: cursor) else { return nil }
                cursor += 1
                for _ in 0 ..< repeatCount {
                    flags.append(flag)
                }
            }
        }

        // Coordinates: deltas with short/same compression.
        var xs: [Double] = []
        var x = 0
        for flag in flags {
            if flag & 0x02 != 0 { // x is u8
                guard let delta = Self.u8(data, at: cursor) else { return nil }
                cursor += 1
                x += (flag & 0x10 != 0) ? delta : -delta
            } else if flag & 0x10 == 0 { // x is i16
                guard let delta = Self.i16(data, at: cursor) else { return nil }
                cursor += 2
                x += delta
            }
            xs.append(Double(x))
        }
        var ys: [Double] = []
        var y = 0
        for flag in flags {
            if flag & 0x04 != 0 { // y is u8
                guard let delta = Self.u8(data, at: cursor) else { return nil }
                cursor += 1
                y += (flag & 0x20 != 0) ? delta : -delta
            } else if flag & 0x20 == 0 { // y is i16
                guard let delta = Self.i16(data, at: cursor) else { return nil }
                cursor += 2
                y += delta
            }
            ys.append(Double(y))
        }
        return (xs, ys, flags, endPoints)
    }

    private func buildSimplePath(xs: [Double], ys: [Double], flags: [Int], endPoints: [Int]) -> Path? {
        let pointCount = xs.count
        var path = Path()
        var contourStart = 0
        for contourEnd in endPoints {
            guard contourEnd >= contourStart, contourEnd < pointCount else { return nil }
            appendContour(
                to: &path,
                points: (contourStart ... contourEnd).map { Point(x: xs[$0], y: ys[$0]) },
                onCurve: (contourStart ... contourEnd).map { flags[$0] & 0x01 != 0 }
            )
            contourStart = contourEnd + 1
        }
        return path
    }

    /// Reconstructs one quadratic contour, synthesizing implied on-curve
    /// midpoints between consecutive off-curve points.
    private func appendContour(to path: inout Path, points: [Point], onCurve: [Bool]) {
        let count = points.count
        guard count >= 2 else { return }

        func midpoint(_ a: Point, _ b: Point) -> Point {
            Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        // Start at an on-curve point, or a synthesized midpoint when none leads.
        let startIndex = onCurve.firstIndex(of: true)
        let start: Point = if let startIndex {
            points[startIndex]
        } else {
            midpoint(points[0], points[1])
        }
        path.move(to: start)

        let rotation = startIndex ?? 0
        var pendingControl: Point?
        for step in 1 ... count {
            let index = (rotation + step) % count
            let point = points[index]
            if onCurve[index] {
                if let control = pendingControl {
                    path.addQuadCurve(to: point, control: control)
                    pendingControl = nil
                } else {
                    path.addLine(to: point)
                }
            } else {
                if let control = pendingControl {
                    let implied = midpoint(control, point)
                    path.addQuadCurve(to: implied, control: control)
                }
                pendingControl = point
            }
        }
        if let control = pendingControl {
            path.addQuadCurve(to: start, control: control)
        }
        path.closeSubpath()
    }

    private func compositeOutline(at glyphOffset: Int, depth: Int) -> Path? {
        guard let components = compositeComponents(at: glyphOffset) else { return nil }
        var path = Path()
        for component in components {
            if let sub = outline(forGlyph: component.glyphIndex, depth: depth + 1) {
                let transform = component.scale.concatenating(.translation(x: component.dx, y: component.dy))
                path.addPath(sub.applying(transform))
            }
        }
        return path
    }

    /// Parses a composite glyph's component records: the referenced glyph, its 2x2 scale/transform,
    /// and (for offset-based components) the x/y placement. `argsAreXY` is false for point-matched
    /// components, whose anchors cannot be varied.
    private func compositeComponents(at glyphOffset: Int) -> [(glyphIndex: Int, dx: Double, dy: Double, scale: AffineTransform, argsAreXY: Bool)]? {
        var cursor = glyphOffset + 10
        var components: [(glyphIndex: Int, dx: Double, dy: Double, scale: AffineTransform, argsAreXY: Bool)] = []
        while true {
            guard let flags = Self.u16(data, at: cursor),
                  let componentIndex = Self.u16(data, at: cursor + 2)
            else { return nil }
            cursor += 4

            let argsAreWords = flags & 0x0001 != 0
            let argsAreXY = flags & 0x0002 != 0
            var dx = 0.0
            var dy = 0.0
            if argsAreWords {
                guard let arg1 = Self.i16(data, at: cursor), let arg2 = Self.i16(data, at: cursor + 2) else { return nil }
                cursor += 4
                if argsAreXY {
                    dx = Double(arg1)
                    dy = Double(arg2)
                }
            } else {
                guard let arg1 = Self.u8(data, at: cursor), let arg2 = Self.u8(data, at: cursor + 1) else { return nil }
                cursor += 2
                if argsAreXY {
                    dx = Double(Int8(truncatingIfNeeded: arg1))
                    dy = Double(Int8(truncatingIfNeeded: arg2))
                }
            }

            var scale = AffineTransform.identity
            if flags & 0x0008 != 0 { // WE_HAVE_A_SCALE
                guard let value = Self.f2dot14(data, at: cursor) else { return nil }
                cursor += 2
                scale = AffineTransform(a: value, b: 0, c: 0, d: value, tx: 0, ty: 0)
            } else if flags & 0x0040 != 0 { // X_AND_Y_SCALE
                guard let scaleX = Self.f2dot14(data, at: cursor),
                      let scaleY = Self.f2dot14(data, at: cursor + 2) else { return nil }
                cursor += 4
                scale = AffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: 0, ty: 0)
            } else if flags & 0x0080 != 0 { // TWO_BY_TWO
                guard let a = Self.f2dot14(data, at: cursor),
                      let b = Self.f2dot14(data, at: cursor + 2),
                      let c = Self.f2dot14(data, at: cursor + 4),
                      let d = Self.f2dot14(data, at: cursor + 6) else { return nil }
                cursor += 8
                scale = AffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0)
            }

            components.append((componentIndex, dx, dy, scale, argsAreXY))
            if flags & 0x0020 == 0 { // no MORE_COMPONENTS
                break
            }
        }
        return components
    }

    // MARK: - Byte Reading

    private static func u8(_ bytes: [UInt8], at offset: Int) -> Int? {
        guard offset >= 0, offset < bytes.count else { return nil }
        return Int(bytes[offset])
    }

    private static func i8(_ bytes: [UInt8], at offset: Int) -> Int? {
        guard let raw = u8(bytes, at: offset) else { return nil }
        return raw > 0x7F ? raw - 0x100 : raw
    }

    private static func u16(_ bytes: [UInt8], at offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
    }

    private static func i16(_ bytes: [UInt8], at offset: Int) -> Int? {
        guard let raw = u16(bytes, at: offset) else { return nil }
        return raw > 0x7FFF ? raw - 0x10000 : raw
    }

    private static func u32(_ bytes: [UInt8], at offset: Int) -> Int? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16) | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
    }

    private static func f2dot14(_ bytes: [UInt8], at offset: Int) -> Double? {
        guard let raw = i16(bytes, at: offset) else { return nil }
        return Double(raw) / 16384.0
    }

    /// A signed 16.16 fixed-point value (the `Fixed` type used by `fvar` coordinates).
    private static func fixed16(_ bytes: [UInt8], at offset: Int) -> Double? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        // Read as UInt32 and reinterpret the two's-complement sign so the math is
        // correct on 32-bit targets (the literals 0x8000_0000 / 0x1_0000_0000
        // overflow a 32-bit Int, e.g. on wasm32).
        let raw = (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        return Double(Int32(bitPattern: raw)) / 65536.0
    }

    private static func tag(_ bytes: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return String(decoding: bytes[offset ..< offset + 4], as: UTF8.self)
    }
}
