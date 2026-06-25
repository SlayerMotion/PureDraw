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
    /// OS/2 typographic ascender in font units. This is the line-spacing ascent
    /// Core Text (and so SwiftUI) uses to compute line height, distinct from the
    /// `hhea` ascent above. Falls back to the `hhea` ascender when the font carries
    /// no `OS/2` table.
    public let typoAscender: Double
    /// OS/2 typographic descender in font units (typically negative). Falls back to
    /// the `hhea` descender when the font carries no `OS/2` table.
    public let typoDescender: Double
    /// OS/2 typographic line gap in font units: the leading added between lines.
    /// Falls back to the `hhea` line gap when the font carries no `OS/2` table.
    public let typoLineGap: Double
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
    /// Long vertical metrics in `vmtx`, from `vhea`. Zero when the font carries no
    /// vertical metrics (`vmtx`/`vhea` absent), the usual case for text fonts.
    private let numberOfVMetrics: Int
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
        // Line height comes from the OS/2 typographic metrics, not hhea: Core Text
        // (and SwiftUI's Text) size lines from sTypoAscender/sTypoDescender/
        // sTypoLineGap, at fixed offsets 68/70/72 of the OS/2 table (present in
        // every OS/2 version, v0 onward). The hhea line gap lives at hhea + 8.
        // OS/2 is an optional table: fall back to hhea metrics when it is absent.
        let hheaLineGap = Self.i16(bytes, at: hhea.offset + 8) ?? 0
        if let os2 = tableDirectory["OS/2"],
           let typoAsc = Self.i16(bytes, at: os2.offset + 68),
           let typoDesc = Self.i16(bytes, at: os2.offset + 70),
           let typoGap = Self.i16(bytes, at: os2.offset + 72)
        {
            typoAscender = Double(typoAsc)
            typoDescender = Double(typoDesc)
            typoLineGap = Double(typoGap)
        } else {
            typoAscender = Double(ascender)
            typoDescender = Double(descender)
            typoLineGap = Double(hheaLineGap)
        }
        numberOfGlyphs = glyphCount
        indexToLocFormat = locFormat
        numberOfHMetrics = max(1, hMetricCount)
        // Vertical metrics are optional: only fonts meant for vertical layout (CJK)
        // carry vhea/vmtx. numOfLongVerMetrics lives at vhea + 34, as the
        // horizontal count lives at hhea + 34.
        if let vhea = tableDirectory["vhea"], let vMetricCount = Self.u16(bytes, at: vhea.offset + 34) {
            numberOfVMetrics = max(1, vMetricCount)
        } else {
            numberOfVMetrics = 0
        }
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

    /// The advance height for a glyph, in font units: how far the pen descends for
    /// the glyph in top-to-bottom vertical layout, from `vmtx`. Returns 0 when the
    /// font has no vertical metrics, the caller's signal to synthesize one (a full
    /// em is the usual fallback). Mirrors `advanceWidth(forGlyph:)`: each long
    /// metric is a 4-byte `advanceHeight, topSideBearing` pair, advanceHeight
    /// first, and glyphs past the long-metric count reuse the last advance.
    public func advanceHeight(forGlyph index: Int) -> Double {
        guard numberOfVMetrics > 0, let vmtx = tables["vmtx"], index >= 0 else { return 0 }
        let metricIndex = min(index, numberOfVMetrics - 1)
        guard let advance = Self.u16(data, at: vmtx.offset + metricIndex * 4) else { return 0 }
        return Double(advance)
    }

    /// The horizontal tracking adjustment, in font units, that the AAT `trak` table
    /// applies to every glyph advance at `pointSize` for the default (normal) track.
    ///
    /// The `trak` table stores a tracking value per (track, size). Core Text applies
    /// the track whose value is `0.0` (normal tracking) and bakes the result into
    /// `CTFontGetAdvancesForGlyphs`, so a sized advance that matches Core Text must add
    /// it. The per-size values are interpolated linearly in point size, holding the end
    /// values for sizes outside the table's range. The amount is a function of size,
    /// not of the glyph, and is the same constant added to each glyph in a run.
    /// Returns 0 when the font has no `trak` table, no horizontal track data, or no
    /// `0.0` track. (Apple TrueType Reference Manual, `trak`.)
    public func horizontalTracking(forPointSize pointSize: Double) -> Double {
        guard let trak = tables["trak"],
              let horizOffset = Self.u16(data, at: trak.offset + 6), horizOffset != 0
        else { return 0 }
        let trackData = trak.offset + horizOffset
        guard let trackCount = Self.u16(data, at: trackData),
              let sizeCount = Self.u16(data, at: trackData + 2),
              let sizeTableOffset = Self.u32(data, at: trackData + 4),
              sizeCount > 0
        else { return 0 }
        // Core Text applies the normal track, the one whose track value is 0.0.
        var valuesBase: Int?
        for index in 0 ..< trackCount {
            let record = trackData + 8 + index * 8
            guard let track = Self.fixed16(data, at: record),
                  let perSizeOffset = Self.u16(data, at: record + 6)
            else { return 0 }
            if track == 0 {
                valuesBase = trak.offset + perSizeOffset
                break
            }
        }
        guard let valuesBase else { return 0 }
        // The point sizes (Fixed) and the normal track's per-size values (font units).
        let sizeBase = trak.offset + sizeTableOffset
        var sizes: [Double] = []
        var values: [Double] = []
        for index in 0 ..< sizeCount {
            guard let size = Self.fixed16(data, at: sizeBase + index * 4),
                  let value = Self.i16(data, at: valuesBase + index * 2)
            else { return 0 }
            sizes.append(size)
            values.append(Double(value))
        }
        if pointSize <= sizes[0] { return values[0] }
        if pointSize >= sizes[sizeCount - 1] { return values[sizeCount - 1] }
        for index in 1 ..< sizeCount where pointSize <= sizes[index] {
            let lo = sizes[index - 1], hi = sizes[index]
            guard hi > lo else { return values[index - 1] }
            let fraction = (pointSize - lo) / (hi - lo)
            return values[index - 1] + fraction * (values[index] - values[index - 1])
        }
        return values[sizeCount - 1]
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
    /// `includeLegacyKern` controls the fallback to the legacy `kern` table when the
    /// font carries no GPOS kerning. The legacy `kern` is a glyph-stream (display
    /// order) table, so a caller shaping a right-to-left run, which kerns before the
    /// bidi reorder, passes `false` to skip it rather than kern the wrong, logical,
    /// adjacencies; GPOS kerning is logical-order and stays.
    public func kerningMap(restrictTo activeFeatures: Set<Int>? = nil, includeLegacyKern: Bool = true, variations: [String: Double] = [:]) -> KerningMap {
        var pairs: [UInt64: Int] = [:]
        var classSubtables: [KerningClassSubtable] = []
        let normalized = variations.isEmpty ? nil : normalizedVariationCoordinates(variations)
        parseGPOSKern(into: &pairs, classSubtables: &classSubtables, restrictTo: activeFeatures, normalized: normalized)
        if pairs.isEmpty, classSubtables.isEmpty, includeLegacyKern {
            parseLegacyKern(into: &pairs)
        }
        return KerningMap(adjustments: pairs, classSubtables: classSubtables)
    }

    /// The x-advance kern value of a ValueRecord at `recordStart`, plus the
    /// instance's delta when the record carries an XAdvance VariationIndex (the
    /// `valueFormat` XAdvDevice bit, 0x40, into the GDEF ItemVariationStore). The
    /// device offset is relative to `subtableBase`. Returns `base` unchanged for a
    /// static font, the default instance, or an ordinary hinting Device table.
    private func variedXAdvance(_ base: Int, valueFormat: Int, recordStart: Int, subtableBase: Int, normalized: [Double]?) -> Int {
        guard let normalized, valueFormat & 0x0040 != 0, let store = gdefItemVariationStoreOffset else { return base }
        let deviceFieldOffset = (valueFormat & 0x003F).nonzeroBitCount * 2
        guard let deviceOffset = Self.u16(data, at: recordStart + deviceFieldOffset), deviceOffset != 0 else { return base }
        return base + variationIndexDelta(at: subtableBase + deviceOffset, store: store, normalized: normalized)
    }

    /// Reads GPOS `kern`-feature pair positioning (PairPos format 1) into `pairs`.
    ///
    /// Simplification (disclosed): the `kern` feature's lookups are gathered from
    /// the FeatureList directly, without per-script or per-language selection,
    /// which matches the common single-`kern`-feature font. Extension lookups
    /// (type 9) wrapping pair positioning are resolved.
    private func parseGPOSKern(
        into pairs: inout [UInt64: Int],
        classSubtables: inout [KerningClassSubtable],
        restrictTo activeFeatures: Set<Int>? = nil,
        normalized: [Double]? = nil
    ) {
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
                if let activeFeatures, !activeFeatures.contains(featureIndex) { continue }
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
                        parsePairPosFormat1(subtable: subtable, normalized: normalized, into: &pairs)
                    } else if posFormat == 2 {
                        parsePairPosFormat2(subtable: subtable, normalized: normalized, into: &classSubtables)
                    }
                }
            }
        }
    }

    /// Decodes a GPOS PairPos format 2 (class-based pair) subtable into a
    /// ``KerningClassSubtable``, reusing the Coverage and ClassDef parsers.
    private func parsePairPosFormat2(subtable: Int, normalized: [Double]?, into classSubtables: inout [KerningClassSubtable]) {
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
                    xAdvances[cell] = variedXAdvance(xAdvance, valueFormat: valueFormat1, recordStart: record, subtableBase: subtable, normalized: normalized)
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
    private func parsePairPosFormat1(subtable: Int, normalized: [Double]?, into pairs: inout [UInt64: Int]) {
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
                let varied = variedXAdvance(xAdvance, valueFormat: valueFormat1, recordStart: record + 2, subtableBase: subtable, normalized: normalized)
                if varied != 0 {
                    pairs[KerningMap.key(firstGlyph: firstGlyph, secondGlyph: secondGlyph)] = varied
                }
            }
        }
    }

    /// Reads the legacy `kern` table into `pairs`, in both layouts a font may use:
    /// the Microsoft version 0 (u16 version and count, subtable format in the
    /// coverage high byte) and the Apple AAT version 1.0 (u32 version and count,
    /// format in the coverage low byte, the layout Helvetica and other classic Apple
    /// fonts carry). Only horizontal, non-cross-stream format-0 pair subtables
    /// contribute to horizontal kerning.
    private func parseLegacyKern(into pairs: inout [UInt64: Int]) {
        guard let kern = tables["kern"] else { return }
        if Self.u16(data, at: kern.offset) == 0 {
            guard let subtableCount = Self.u16(data, at: kern.offset + 2) else { return }
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
                if format == 0, isHorizontal {
                    // Subtable header is version, length, coverage (6 bytes); the
                    // format-0 nPairs field follows.
                    readKernFormat0(pairsHeader: subtableOffset + 6, into: &pairs)
                }
                subtableOffset += length
            }
        } else if Self.u32(data, at: kern.offset) == 0x0001_0000 {
            guard let subtableCount = Self.u32(data, at: kern.offset + 4) else { return }
            var subtableOffset = kern.offset + 8
            for _ in 0 ..< subtableCount {
                guard let length = Self.u32(data, at: subtableOffset),
                      let coverage = Self.u16(data, at: subtableOffset + 4),
                      length > 0
                else {
                    return
                }
                let format = coverage & 0xFF
                let vertical = (coverage & 0x8000) != 0
                let crossStream = (coverage & 0x4000) != 0
                if format == 0, !vertical, !crossStream {
                    // Subtable header is length, coverage, tupleIndex (8 bytes); the
                    // format-0 nPairs field follows.
                    readKernFormat0(pairsHeader: subtableOffset + 8, into: &pairs)
                }
                subtableOffset += length
            }
        }
    }

    /// Reads a format-0 `kern` subtable's pair list, whose `pairsHeader` is the u16
    /// `nPairs` field; the pair records follow the 8-byte search header. Each record
    /// is (left glyph, right glyph, i16 value), inserted into `pairs`.
    private func readKernFormat0(pairsHeader: Int, into pairs: inout [UInt64: Int]) {
        guard let pairCount = Self.u16(data, at: pairsHeader) else { return }
        let pairsStart = pairsHeader + 8
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

    // MARK: - Substitution

    /// The font's `liga` ligature substitution rules, for the shaping tier to
    /// apply (for example `f` `i` becoming the `fi` ligature).
    ///
    /// This reads GSUB ligature substitution (lookup type 4) under the `liga`
    /// (standard) and `rlig` (required, the Arabic lam-alef) features, resolving
    /// extension lookups (type 7). Single substitution (type 1) is
    /// ``singleSubstitutions(feature:)``; the contextual lookups are the next
    /// slices of SlayerMotion/PureDraw#140.
    public func ligatures(restrictTo activeFeatures: Set<Int>? = nil) -> [LigatureSubstitution] {
        var result: [LigatureSubstitution] = []
        parseGSUBLigatures(into: &result, restrictTo: activeFeatures)
        return result
    }

    /// Whether the font carries an AAT `morx` glyph metamorphosis table, which Core
    /// Text shapes through in preference to OpenType GSUB when present.
    public var hasMorx: Bool {
        tables["morx"] != nil
    }

    /// Applies the font's AAT `morx` chain to `glyphs`, returning the transformed
    /// glyph run with each glyph tagged by the input index it derives from. Returns
    /// the input unchanged when the font carries no `morx` table. PureDraw owns the
    /// byte-level state machines; the shaping tier consumes the structured result.
    public func applyMorx(_ glyphs: [MorxGlyph]) -> [MorxGlyph] {
        guard let morx = tables["morx"] else { return glyphs }
        return MorxReader(data: data, base: morx.offset, glyphCount: numberOfGlyphs).apply(glyphs)
    }

    /// The AAT `kerx` horizontal kerning adjustments for `glyphs`, one per glyph:
    /// element `i` is the advance adjustment to apply before glyph `i` (the kerning
    /// between glyph `i - 1` and glyph `i`), in font units, with element 0 zero. All
    /// zeros when the font carries no `kerx` table. This is the AAT pair kerning
    /// (format 2) that complements the glyph advances on a `morx`-shaped run.
    public func kerxHorizontalAdjustments(_ glyphs: [Int]) -> [Int] {
        guard let kerx = tables["kerx"] else { return [Int](repeating: 0, count: glyphs.count) }
        return KerxReader(data: data, base: kerx.offset, ankrBase: tables["ankr"]?.offset, glyphCount: numberOfGlyphs).horizontalAdjustments(glyphs)
    }

    /// The AAT `kerx` format-4 anchor attachments for `glyphs`: each says a glyph
    /// attaches to an earlier glyph by aligning anchor points resolved from the
    /// `ankr` table. Empty when the font carries no `kerx` or `ankr` table. This is
    /// the AAT mark-to-base positioning that seats, for example, a Myanmar subscript
    /// under its base. The shaping tier applies them with its pen positions.
    public func kerxAnchorAttachments(_ glyphs: [Int]) -> [KerxAnchorAttachment] {
        guard let kerx = tables["kerx"] else { return [] }
        return KerxReader(data: data, base: kerx.offset, ankrBase: tables["ankr"]?.offset, glyphCount: numberOfGlyphs).anchorAttachments(glyphs)
    }

    /// The font's ligature substitutions (GSUB lookup type 4) under a single
    /// feature tag, for example the Khmer below-base forms feature `blwf`, whose
    /// coeng + consonant ligature forms the subscript consonant, or the pre-base
    /// `pref`. Mirrors ``singleSubstitutions(feature:)`` for ligatures: the broad
    /// ``ligatures(restrictTo:)`` gathers only `liga`/`rlig`/`ccmp`, so a
    /// script-form feature that carries its conjuncts as ligatures needs this
    /// per-tag accessor. Extension lookups (type 7) are resolved.
    public func ligatures(feature tag: String, restrictTo activeFeatures: Set<Int>? = nil) -> [LigatureSubstitution] {
        var result: [LigatureSubstitution] = []
        forEachGSUBSubtable(matching: { $0 == tag }, restrictTo: activeFeatures) { subtable, effectiveType, _ in
            if effectiveType == 4 {
                parseLigatureSubst(subtable: subtable, into: &result)
            }
        }
        return result
    }

    private func parseGSUBLigatures(into result: inout [LigatureSubstitution], restrictTo activeFeatures: Set<Int>?) {
        // `liga` is the standard Latin ligatures; `rlig` is required ligatures,
        // used for the Arabic lam-alef among others; `ccmp` composes glyphs, for
        // example combining an Arabic shadda and a vowel mark into one glyph.
        // Only the ligature (type 4) part of `ccmp` is read here.
        forEachGSUBSubtable(matching: { $0 == "liga" || $0 == "rlig" || $0 == "ccmp" }, restrictTo: activeFeatures) { subtable, effectiveType, _ in
            if effectiveType == 4 {
                parseLigatureSubst(subtable: subtable, into: &result)
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
    public func singleSubstitutions(feature: String, restrictTo activeFeatures: Set<Int>? = nil) -> [Int: Int] {
        var result: [Int: Int] = [:]
        forEachGSUBSubtable(matching: { $0 == feature }, restrictTo: activeFeatures) { subtable, effectiveType, _ in
            if effectiveType == 1 {
                parseSingleSubst(subtable: subtable, into: &result)
            }
        }
        return result
    }

    /// The font's multiple-substitution map (GSUB lookup type 2) for a feature
    /// tag: each covered glyph maps to the ordered sequence of glyphs it expands
    /// into, for example a precomposed glyph decomposed into a base plus a
    /// combining mark under `ccmp`. Extension lookups (type 7) are resolved.
    /// (OpenType GSUB: Lookup Type 2, "Multiple Substitution Subtable",
    /// MultipleSubstFormat1.)
    public func multipleSubstitutions(feature: String, restrictTo activeFeatures: Set<Int>? = nil) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        forEachGSUBSubtable(matching: { $0 == feature }, restrictTo: activeFeatures) { subtable, effectiveType, _ in
            if effectiveType == 2 {
                parseSequenceSubst(subtable: subtable, into: &result)
            }
        }
        return result
    }

    /// The font's alternate-substitution map (GSUB lookup type 3) for a feature
    /// tag: each covered glyph maps to its list of alternate glyphs, in the order
    /// the font lists them. Which alternate is used is a user selection (the
    /// `aalt`/`salt`/`cvNN` feature value), so this accessor exposes the choices
    /// and the shaping tier applies a requested index rather than picking one
    /// here. Extension lookups (type 7) are resolved. (OpenType GSUB: Lookup Type
    /// 3, "Alternate Substitution Subtable", AlternateSubstFormat1.)
    public func alternateSubstitutions(feature: String, restrictTo activeFeatures: Set<Int>? = nil) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        forEachGSUBSubtable(matching: { $0 == feature }, restrictTo: activeFeatures) { subtable, effectiveType, _ in
            if effectiveType == 3 {
                parseSequenceSubst(subtable: subtable, into: &result)
            }
        }
        return result
    }

    /// The font's GSUB chaining contextual substitutions (lookup type 6, format
    /// 3) under `feature`, with nested type-1 single substitutions resolved into
    /// the rules. These substitute a glyph only in a matching neighbourhood (an
    /// Arabic `rclt` rule that lifts a vowel mark to a high variant after a base
    /// letter). Empty when the font carries no such rules for the feature. Format
    /// 1 and 2 contexts, and nested lookups other than type 1, are not collected.
    public func chainingSubstitutions(feature: String, restrictTo activeFeatures: Set<Int>? = nil) -> [ChainingSubstitution] {
        var result: [ChainingSubstitution] = []
        forEachGSUBSubtable(matching: { $0 == feature }, restrictTo: activeFeatures) { subtable, effectiveType, lookupFlag in
            // IgnoreMarks (0x0008) skips all marks; UseMarkFilteringSet (0x0010)
            // skips marks outside a named set. Both are treated as skipping; the
            // filtering-set refinement is approximated as skipping every mark,
            // exact when the context's non-input positions are non-marks (a
            // base-letter backtrack, for example).
            let skipsMarks = lookupFlag & (0x0008 | 0x0010) != 0
            if effectiveType == 6 {
                parseChainContext(subtable: subtable, ignoreMarks: skipsMarks, into: &result)
            } else if effectiveType == 5 {
                parseContext(subtable: subtable, ignoreMarks: skipsMarks, into: &result)
            }
        }
        return result
    }

    /// The indices of the GSUB lookups selected by the features whose tag is in
    /// `tags`, in lookup-list order (ascending index), deduplicated. This is the
    /// order OpenType applies lookups: by position in the LookupList, not by
    /// feature, so two features sharing a lookup apply it once and a lookup's
    /// effect is seen by every later lookup. `restrictTo` filters by a script's
    /// active feature indices, as for the per-feature accessors. The shaping tier
    /// walks these in order and applies each through ``gsubLookup(at:)``.
    public func gsubLookupIndices(features tags: Set<String>, restrictTo activeFeatures: Set<Int>? = nil) -> [Int] {
        guard let gsub = tables["GSUB"], let featureListOffset = Self.u16(data, at: gsub.offset + 6) else { return [] }
        let featureList = gsub.offset + featureListOffset
        guard let featureCount = Self.u16(data, at: featureList) else { return [] }
        var indices: Set<Int> = []
        for featureIndex in 0 ..< featureCount {
            if let activeFeatures, !activeFeatures.contains(featureIndex) { continue }
            let record = featureList + 2 + featureIndex * 6
            guard let tag = Self.tag(data, at: record), tags.contains(tag),
                  let featureOffset = Self.u16(data, at: record + 4)
            else {
                continue
            }
            let featureTable = featureList + featureOffset
            guard let lookupIndexCount = Self.u16(data, at: featureTable + 2) else { continue }
            for slot in 0 ..< lookupIndexCount {
                if let index = Self.u16(data, at: featureTable + 4 + slot * 2) { indices.insert(index) }
            }
        }
        return indices.sorted()
    }

    /// The parsed GSUB lookup at LookupList index `index`, or nil when the index is
    /// out of range. Type-7 extension lookups are resolved to their effective type.
    /// The lookup's subtables are merged into one typed value: single, multiple,
    /// alternate, and ligature subtables accumulate; contextual subtables (types 5
    /// and 6) concatenate their rules. A type this model does not represent yields
    /// ``GSUBLookup/Kind/unsupported`` so the shaping tier can still walk lookup
    /// order. The contextual rules name nested lookups by index, which the shaper
    /// resolves through this same accessor, so contextual recursion is possible.
    public func gsubLookup(at index: Int) -> GSUBLookup? {
        var lookupType: Int?
        var flag = 0
        var single: [Int: Int] = [:]
        var multiple: [Int: [Int]] = [:]
        var alternate: [Int: [Int]] = [:]
        var ligature: [LigatureSubstitution] = []
        var context: [GSUBContextRule] = []
        var reverse: [ReverseChainingSubstitution] = []
        forEachGSUBLookupSubtable(at: index) { subtable, effectiveType, lookupFlag in
            lookupType = effectiveType
            flag = lookupFlag
            let skipsMarks = lookupFlag & (0x0008 | 0x0010) != 0
            switch effectiveType {
            case 1: parseSingleSubst(subtable: subtable, into: &single)
            case 2: parseSequenceSubst(subtable: subtable, into: &multiple)
            case 3: parseSequenceSubst(subtable: subtable, into: &alternate)
            case 4: parseLigatureSubst(subtable: subtable, into: &ligature)
            case 5: parseContextRecords(subtable: subtable, chaining: false, into: &context)
            case 6: parseContextRecords(subtable: subtable, chaining: true, into: &context)
            case 8: parseReverseChainSubst(subtable: subtable, ignoreMarks: skipsMarks, into: &reverse)
            default: break
            }
        }
        guard let lookupType else { return nil }
        // IgnoreMarks (0x0008) skips every mark; UseMarkFilteringSet (0x0010) skips
        // only marks outside a named GDEF mark glyph set. They are distinct: the
        // filtering set is read separately, not folded into ignore-all-marks.
        let ignoreMarks = flag & 0x0008 != 0
        let markAttachmentType = (flag & 0xFF00) >> 8
        let markFilteringSet = flag & 0x0010 != 0 ? gsubLookupMarkFilteringSet(at: index) : nil
        let kind: GSUBLookup.Kind = switch lookupType {
        case 1: .single(single)
        case 2: .multiple(multiple)
        case 3: .alternate(alternate)
        case 4: .ligature(ligature)
        case 5, 6: .context(context)
        case 8: .reverseChainSingle(reverse)
        default: .unsupported
        }
        return GSUBLookup(kind: kind, ignoreMarks: ignoreMarks, markAttachmentType: markAttachmentType, markFilteringSet: markFilteringSet)
    }

    /// Decodes a GSUB contextual (type 5) or chained contextual (type 6) subtable
    /// into ``GSUBContextRule`` values that name nested lookups by index. All three
    /// OpenType formats are read: format 1 lists explicit glyph sequences, format 2
    /// lists class sequences (expanded here to glyph sets through the subtable's
    /// class definitions), and format 3 lists coverage sequences. `chaining`
    /// selects whether backtrack and lookahead sequences are present.
    private func parseContextRecords(subtable: Int, chaining: Bool, into result: inout [GSUBContextRule]) {
        switch Self.u16(data, at: subtable) {
        case 1: parseContextFormat1(subtable: subtable, chaining: chaining, into: &result)
        case 2: parseContextFormat2(subtable: subtable, chaining: chaining, into: &result)
        case 3: parseContextFormat3(subtable: subtable, chaining: chaining, into: &result)
        default: break
        }
    }

    /// Reads `count` SequenceLookupRecords (each a 2-byte sequence index and a
    /// 2-byte nested lookup index) starting at `cursor`.
    private func readSequenceLookupRecords(at cursor: Int, count: Int) -> [GSUBContextRule.Record] {
        var records: [GSUBContextRule.Record] = []
        records.reserveCapacity(count)
        for slot in 0 ..< count {
            guard let sequenceIndex = Self.u16(data, at: cursor + slot * 4),
                  let lookupIndex = Self.u16(data, at: cursor + slot * 4 + 2)
            else {
                break
            }
            records.append(.init(sequenceIndex: sequenceIndex, lookupIndex: lookupIndex))
        }
        return records
    }

    /// Per-class glyph sets for a class definition, including class 0 as the
    /// complement: every glyph the table does not assign a non-zero class. The
    /// complement is needed because class-based contextual rules match class 0
    /// (any glyph not otherwise classified) as a context position.
    private func classGlyphSets(_ classDef: OpenTypeClassDef) -> [Int: Set<Int>] {
        var sets: [Int: Set<Int>] = [:]
        var assigned: Set<Int> = []
        for (glyph, value) in classDef.assignments {
            sets[value, default: []].insert(glyph)
            assigned.insert(glyph)
        }
        var zero: Set<Int> = []
        zero.reserveCapacity(max(0, numberOfGlyphs - assigned.count))
        for glyph in 0 ..< numberOfGlyphs where !assigned.contains(glyph) {
            zero.insert(glyph)
        }
        sets[0] = zero
        return sets
    }

    /// The per-class glyph sets for the class definition at `offset` (relative to
    /// `subtableBase`), or all glyphs in class 0 when the offset is the null offset
    /// 0. A class-based chaining subtable uses a null backtrack or lookahead class
    /// definition when no rule has backtrack or lookahead, and a null offset is not
    /// a class table to parse: every glyph is then class 0 (a class-0 context
    /// position matches anything, a non-zero one matches nothing), which is exactly
    /// the absent-classification meaning. Parsing at `subtableBase` instead would
    /// misread the subtable header as a class table and drop the whole lookup.
    private func gsubClassGlyphSets(atOffset offset: Int, subtableBase: Int) -> [Int: Set<Int>] {
        guard offset != 0, let classDef = OpenTypeClassDef(data: data, offset: subtableBase + offset) else {
            return [0: Set(0 ..< numberOfGlyphs)]
        }
        return classGlyphSets(classDef)
    }

    /// Decodes a type-5 ContextSubstFormat3 or type-6 ChainContextSubstFormat3
    /// subtable: coverage sequences for the input (and, when chaining, backtrack
    /// and lookahead), then the SequenceLookupRecords. The two layouts differ in
    /// where the record count sits: a chaining subtable puts it last, after the
    /// lookahead; a plain context subtable (type 5) puts seqLookupCount right after
    /// the input glyph count, before the input coverages.
    private func parseContextFormat3(subtable: Int, chaining: Bool, into result: inout [GSUBContextRule]) {
        if chaining {
            var cursor = subtable + 2
            guard let backtrack = readCoverageSequence(at: &cursor, subtableBase: subtable),
                  let input = readCoverageSequence(at: &cursor, subtableBase: subtable),
                  let lookahead = readCoverageSequence(at: &cursor, subtableBase: subtable),
                  let recordCount = Self.u16(data, at: cursor)
            else {
                return
            }
            cursor += 2
            let records = readSequenceLookupRecords(at: cursor, count: recordCount)
            guard !records.isEmpty, !input.isEmpty else { return }
            result.append(.init(backtrack: backtrack, input: input, lookahead: lookahead, records: records))
        } else {
            guard let glyphCount = Self.u16(data, at: subtable + 2),
                  let recordCount = Self.u16(data, at: subtable + 4)
            else {
                return
            }
            var cursor = subtable + 6
            var input: [Set<Int>] = []
            for _ in 0 ..< glyphCount {
                guard let coverageOffset = Self.u16(data, at: cursor),
                      let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
                else {
                    return
                }
                input.append(coverage.coveredGlyphs)
                cursor += 2
            }
            let records = readSequenceLookupRecords(at: cursor, count: recordCount)
            guard !records.isEmpty, !input.isEmpty else { return }
            result.append(.init(backtrack: [], input: input, lookahead: [], records: records))
        }
    }

    /// Decodes a type-5 ContextSubstFormat1 or type-6 ChainContextSubstFormat1
    /// subtable: a coverage selects a rule set per first-input glyph; each rule
    /// lists explicit glyph ids for the rest of the input (and, when chaining, the
    /// backtrack and lookahead), then its nested lookup records.
    private func parseContextFormat1(subtable: Int, chaining: Bool, into result: inout [GSUBContextRule]) {
        guard let coverageOffset = Self.u16(data, at: subtable + 2),
              let ruleSetCount = Self.u16(data, at: subtable + 4),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
        else {
            return
        }
        for ruleSetIndex in 0 ..< ruleSetCount {
            guard let firstGlyph = coverage.glyph(atIndex: ruleSetIndex),
                  let ruleSetOffset = Self.u16(data, at: subtable + 6 + ruleSetIndex * 2), ruleSetOffset != 0
            else {
                continue
            }
            let ruleSet = subtable + ruleSetOffset
            guard let ruleCount = Self.u16(data, at: ruleSet) else { continue }
            for ruleIndex in 0 ..< ruleCount {
                guard let ruleOffset = Self.u16(data, at: ruleSet + 2 + ruleIndex * 2), ruleOffset != 0 else { continue }
                var cursor = ruleSet + ruleOffset
                var backtrack: [Set<Int>] = []
                if chaining {
                    guard let glyphs = readGlyphSequence(at: &cursor) else { continue }
                    backtrack = glyphs.map { [$0] }
                }
                guard let inputCount = Self.u16(data, at: cursor) else { continue }
                cursor += 2
                // A type-5 SequenceRule lists seqLookupCount right after glyphCount,
                // before the input; a type-6 ChainSequenceRule lists it last.
                var recordCount = 0
                if !chaining {
                    guard let count = Self.u16(data, at: cursor) else { continue }
                    recordCount = count
                    cursor += 2
                }
                var input: [Set<Int>] = [[firstGlyph]]
                var valid = true
                for _ in 0 ..< max(0, inputCount - 1) {
                    guard let glyph = Self.u16(data, at: cursor) else { valid = false
                        break
                    }
                    input.append([glyph])
                    cursor += 2
                }
                guard valid else { continue }
                if chaining {
                    guard let glyphs = readGlyphSequence(at: &cursor) else { continue }
                    let lookahead = glyphs.map { Set([$0]) }
                    guard let count = Self.u16(data, at: cursor) else { continue }
                    cursor += 2
                    let records = readSequenceLookupRecords(at: cursor, count: count)
                    guard !records.isEmpty else { continue }
                    result.append(.init(backtrack: backtrack, input: input, lookahead: lookahead, records: records))
                    continue
                }
                let records = readSequenceLookupRecords(at: cursor, count: recordCount)
                guard !records.isEmpty else { continue }
                result.append(.init(backtrack: backtrack, input: input, lookahead: [], records: records))
            }
        }
    }

    /// Decodes a type-5 ContextSubstFormat2 or type-6 ChainContextSubstFormat2
    /// subtable: class definitions classify the glyphs, a rule set is selected per
    /// first-input class, and each rule lists class values for the rest of the
    /// input (and, when chaining, the backtrack and lookahead). Each class value is
    /// expanded to its glyph set so the rule matches like the other formats.
    private func parseContextFormat2(subtable: Int, chaining: Bool, into result: inout [GSUBContextRule]) {
        guard let coverageOffset = Self.u16(data, at: subtable + 2),
              OpenTypeCoverage(data: data, offset: subtable + coverageOffset) != nil
        else {
            return
        }
        let backtrackSets: [Int: Set<Int>]
        let inputSets: [Int: Set<Int>]
        let lookaheadSets: [Int: Set<Int>]
        var cursor = subtable + 4
        if chaining {
            guard let backOffset = Self.u16(data, at: cursor),
                  let inputOffset = Self.u16(data, at: cursor + 2),
                  let aheadOffset = Self.u16(data, at: cursor + 4)
            else {
                return
            }
            backtrackSets = gsubClassGlyphSets(atOffset: backOffset, subtableBase: subtable)
            inputSets = gsubClassGlyphSets(atOffset: inputOffset, subtableBase: subtable)
            lookaheadSets = gsubClassGlyphSets(atOffset: aheadOffset, subtableBase: subtable)
            cursor += 6
        } else {
            guard let classDefOffset = Self.u16(data, at: cursor) else { return }
            let sets = gsubClassGlyphSets(atOffset: classDefOffset, subtableBase: subtable)
            backtrackSets = sets
            inputSets = sets
            lookaheadSets = sets
            cursor += 2
        }
        guard let ruleSetCount = Self.u16(data, at: cursor) else { return }
        cursor += 2
        let ruleSetBase = cursor
        for ruleSetIndex in 0 ..< ruleSetCount {
            guard let ruleSetOffset = Self.u16(data, at: ruleSetBase + ruleSetIndex * 2), ruleSetOffset != 0 else { continue }
            let ruleSet = subtable + ruleSetOffset
            guard let ruleCount = Self.u16(data, at: ruleSet) else { continue }
            for ruleIndex in 0 ..< ruleCount {
                guard let ruleOffset = Self.u16(data, at: ruleSet + 2 + ruleIndex * 2), ruleOffset != 0 else { continue }
                var rule = ruleSet + ruleOffset
                var backtrack: [Set<Int>] = []
                if chaining {
                    guard let classes = readGlyphSequence(at: &rule) else { continue }
                    backtrack = classes.map { backtrackSets[$0] ?? [] }
                }
                guard let inputCount = Self.u16(data, at: rule) else { continue }
                rule += 2
                // A type-5 ClassSequenceRule lists seqLookupCount right after the
                // input glyph count, before the input; a type-6 rule lists it last.
                var recordCount = 0
                if !chaining {
                    guard let count = Self.u16(data, at: rule) else { continue }
                    recordCount = count
                    rule += 2
                }
                var input: [Set<Int>] = [inputSets[ruleSetIndex] ?? []]
                var valid = true
                for _ in 0 ..< max(0, inputCount - 1) {
                    guard let value = Self.u16(data, at: rule) else { valid = false
                        break
                    }
                    input.append(inputSets[value] ?? [])
                    rule += 2
                }
                guard valid else { continue }
                if chaining {
                    guard let classes = readGlyphSequence(at: &rule) else { continue }
                    let lookahead = classes.map { lookaheadSets[$0] ?? [] }
                    guard let count = Self.u16(data, at: rule) else { continue }
                    rule += 2
                    let records = readSequenceLookupRecords(at: rule, count: count)
                    guard !records.isEmpty else { continue }
                    result.append(.init(backtrack: backtrack, input: input, lookahead: lookahead, records: records))
                    continue
                }
                let records = readSequenceLookupRecords(at: rule, count: recordCount)
                guard !records.isEmpty else { continue }
                result.append(.init(backtrack: backtrack, input: input, lookahead: [], records: records))
            }
        }
    }

    /// Reads a count-prefixed list of u16 values (glyph ids or class values),
    /// advancing `cursor` past it. The count is at `cursor`.
    private func readGlyphSequence(at cursor: inout Int) -> [Int]? {
        guard let count = Self.u16(data, at: cursor) else { return nil }
        cursor += 2
        var values: [Int] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count {
            guard let value = Self.u16(data, at: cursor) else { return nil }
            values.append(value)
            cursor += 2
        }
        return values
    }

    /// The font's GSUB reverse chaining single substitutions (lookup type 8) under
    /// `feature`: a covered glyph becomes a fixed substitute when its backtrack and
    /// lookahead match. The shaping tier applies these to a run in reverse. Empty
    /// when the font carries no such rules for the feature; extension lookups (type
    /// 7) are resolved. `restrictTo` filters by a script's active feature indices.
    public func reverseChainingSubstitutions(feature: String, restrictTo activeFeatures: Set<Int>? = nil) -> [ReverseChainingSubstitution] {
        var result: [ReverseChainingSubstitution] = []
        forEachGSUBSubtable(matching: { $0 == feature }, restrictTo: activeFeatures) { subtable, effectiveType, lookupFlag in
            if effectiveType == 8 {
                let skipsMarks = lookupFlag & (0x0008 | 0x0010) != 0
                parseReverseChainSubst(subtable: subtable, ignoreMarks: skipsMarks, into: &result)
            }
        }
        return result
    }

    /// Decodes a GSUB ReverseChainSingleSubstFormat1 (type 8) subtable: an input
    /// coverage with an aligned array of substitute glyphs, framed by backtrack and
    /// lookahead coverage sequences. The substitute for the covered glyph at index
    /// i is `substituteGlyphIDs[i]`.
    private func parseReverseChainSubst(subtable: Int, ignoreMarks: Bool, into result: inout [ReverseChainingSubstitution]) {
        guard Self.u16(data, at: subtable) == 1,
              let coverageOffset = Self.u16(data, at: subtable + 2),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
        else {
            return
        }
        var cursor = subtable + 4
        guard let backtrack = readCoverageSequence(at: &cursor, subtableBase: subtable),
              let lookahead = readCoverageSequence(at: &cursor, subtableBase: subtable),
              let glyphCount = Self.u16(data, at: cursor)
        else {
            return
        }
        cursor += 2
        var mapping: [Int: Int] = [:]
        for index in 0 ..< glyphCount {
            guard let inputGlyph = coverage.glyph(atIndex: index),
                  let substitute = Self.u16(data, at: cursor + index * 2)
            else {
                continue
            }
            mapping[inputGlyph] = substitute
        }
        guard !mapping.isEmpty else { return }
        result.append(.init(backtrack: backtrack, lookahead: lookahead, mapping: mapping, ignoreMarks: ignoreMarks))
    }

    // MARK: - Feature selection (ScriptList -> Script -> LangSys)

    /// The GSUB feature indices active for an OpenType `script` tag (`latn`,
    /// `arab`, `DFLT`, ...) and an optional `language` system tag, resolved
    /// through the ScriptList. This is the selection layer the OpenType spec puts
    /// in front of the feature list: a feature applies only when the run's script
    /// (and language) reaches it, not merely because the font carries a record
    /// with that tag. When the script is absent the `DFLT` script is tried; when
    /// the language is absent or unknown the script's default language system is
    /// used; an unset required feature (0xFFFF) is omitted. Empty when the font
    /// has no GSUB, no matching (or `DFLT`) script, or no default language system.
    /// (OpenType Layout Common Table Formats: ScriptList, Script, LangSys.)
    public func gsubFeatureIndices(script: String, language: String? = nil) -> Set<Int> {
        gsubFeatureIndices(scripts: [script], language: language)
    }

    /// As ``gsubFeatureIndices(script:language:)`` but trying several script tags
    /// in order: the first tag the font's ScriptList actually carries selects the
    /// features (so a modern v2 tag is preferred to its v1 fallback), and `DFLT`
    /// is used when none of them is present.
    public func gsubFeatureIndices(scripts: [String], language: String? = nil) -> Set<Int> {
        layoutFeatureIndices(tableTag: "GSUB", scripts: scripts, language: language)
    }

    /// The GPOS feature indices active for an OpenType `script` and optional
    /// `language`, resolved through the ScriptList exactly as
    /// ``gsubFeatureIndices(script:language:)``.
    public func gposFeatureIndices(script: String, language: String? = nil) -> Set<Int> {
        gposFeatureIndices(scripts: [script], language: language)
    }

    /// As ``gposFeatureIndices(script:language:)`` but trying several script tags
    /// in order, like ``gsubFeatureIndices(scripts:language:)``.
    public func gposFeatureIndices(scripts: [String], language: String? = nil) -> Set<Int> {
        layoutFeatureIndices(tableTag: "GPOS", scripts: scripts, language: language)
    }

    /// Resolves the active feature indices for `tableTag` (`GSUB`/`GPOS`) by
    /// walking ScriptList -> Script -> LangSys. The first of `scripts` whose Script
    /// table is present wins; otherwise the `DFLT` script is tried. The language's
    /// named system is used when present, otherwise the default language system.
    private func layoutFeatureIndices(tableTag: String, scripts: [String], language: String?) -> Set<Int> {
        guard let table = tables[tableTag], let scriptListOffset = Self.u16(data, at: table.offset + 4) else { return [] }
        let scriptList = table.offset + scriptListOffset
        let present = scripts.lazy.compactMap { scriptTableOffset(in: scriptList, tag: $0) }.first
        guard let scriptRelative = present ?? scriptTableOffset(in: scriptList, tag: "DFLT") else { return [] }
        let scriptTable = scriptList + scriptRelative
        guard let langSysRelative = langSysTableOffset(in: scriptTable, language: language) else { return [] }
        return featureIndices(atLangSys: scriptTable + langSysRelative)
    }

    /// The offset, relative to the ScriptList, of the Script table for `tag`, or
    /// `nil` when the ScriptList has no such script. Each ScriptRecord is a 4-byte
    /// tag and a 2-byte offset.
    private func scriptTableOffset(in scriptList: Int, tag: String) -> Int? {
        guard let count = Self.u16(data, at: scriptList) else { return nil }
        for index in 0 ..< count {
            let record = scriptList + 2 + index * 6
            if Self.tag(data, at: record) == tag {
                return Self.u16(data, at: record + 4)
            }
        }
        return nil
    }

    /// The offset, relative to the Script table, of the selected LangSys: the
    /// named system for `language` when the Script lists it, otherwise the default
    /// language system. `nil` when neither the requested language nor a default is
    /// present (a Script may carry only named systems). Each LangSysRecord is a
    /// 4-byte tag and a 2-byte offset; the default offset sits at the Script table
    /// start and is `0` when absent.
    private func langSysTableOffset(in scriptTable: Int, language: String?) -> Int? {
        if let language, let count = Self.u16(data, at: scriptTable + 2) {
            for index in 0 ..< count {
                let record = scriptTable + 4 + index * 6
                if Self.tag(data, at: record) == language {
                    return Self.u16(data, at: record + 4)
                }
            }
        }
        guard let defaultOffset = Self.u16(data, at: scriptTable), defaultOffset != 0 else { return nil }
        return defaultOffset
    }

    /// The feature indices a LangSys lists, including its required feature when
    /// set (`requiredFeatureIndex` other than 0xFFFF). The LangSys layout is
    /// `lookupOrderOffset`, `requiredFeatureIndex`, `featureIndexCount`, then the
    /// `featureIndices` array.
    private func featureIndices(atLangSys langSys: Int) -> Set<Int> {
        var indices: Set<Int> = []
        if let required = Self.u16(data, at: langSys + 2), required != 0xFFFF {
            indices.insert(required)
        }
        guard let count = Self.u16(data, at: langSys + 4) else { return indices }
        for index in 0 ..< count {
            if let featureIndex = Self.u16(data, at: langSys + 6 + index * 2) {
                indices.insert(featureIndex)
            }
        }
        return indices
    }

    /// Whether `glyph` is a mark, per the GDEF GlyphClassDef (class 3). Used to
    /// skip marks when a lookup carries the `IgnoreMarks` flag. False when the
    /// font has no GDEF class definition.
    public func isMarkGlyph(_ glyph: Int) -> Bool {
        guard let gdef = tables["GDEF"],
              let classDefOffset = Self.u16(data, at: gdef.offset + 4), classDefOffset != 0,
              let classDef = OpenTypeClassDef(data: data, offset: gdef.offset + classDefOffset)
        else {
            return false
        }
        return classDef.classValue(forGlyph: glyph) == 3
    }

    /// The GDEF mark attachment class of `glyph` (the MarkAttachClassDef table), or
    /// 0 when the glyph has no class or the font has no such table. A lookup whose
    /// flag carries a mark attachment type skips every mark whose class differs from
    /// that type, so a contextual rule can match across one kind of mark (a Nastaliq
    /// dot) while stepping over another (a spacer). (OpenType GDEF: MarkAttachClassDef.)
    public func markAttachmentClass(_ glyph: Int) -> Int {
        guard let gdef = tables["GDEF"],
              let classDefOffset = Self.u16(data, at: gdef.offset + 10), classDefOffset != 0,
              let classDef = OpenTypeClassDef(data: data, offset: gdef.offset + classDefOffset)
        else {
            return 0
        }
        return classDef.classValue(forGlyph: glyph)
    }

    /// Whether `glyph` is in the GDEF mark glyph set numbered `set` (the
    /// MarkGlyphSetsDef table, GDEF version 1.2 and later). A lookup whose flag
    /// carries UseMarkFilteringSet skips every mark not in its named set, so a rule
    /// can match across one kind of mark (a Hebrew vowel point) while keeping
    /// another (the shin dot). False when the font has no mark glyph sets.
    public func markFilterSetContains(set setIndex: Int, glyph: Int) -> Bool {
        guard let gdef = tables["GDEF"],
              let minor = Self.u16(data, at: gdef.offset + 2), minor >= 2,
              let setsOffset = Self.u16(data, at: gdef.offset + 12), setsOffset != 0
        else {
            return false
        }
        let base = gdef.offset + setsOffset
        guard Self.u16(data, at: base) == 1,
              let count = Self.u16(data, at: base + 2), setIndex >= 0, setIndex < count,
              let coverageOffset = Self.u32(data, at: base + 4 + setIndex * 4),
              let coverage = OpenTypeCoverage(data: data, offset: base + coverageOffset)
        else {
            return false
        }
        return coverage.coveredGlyphs.contains(glyph)
    }

    /// The mark filtering-set index of the GSUB lookup at `index`, or nil when its
    /// flag does not carry UseMarkFilteringSet. The index follows the subtable
    /// offsets in the Lookup table and names a set in ``markFilterSetContains(set:glyph:)``.
    private func gsubLookupMarkFilteringSet(at index: Int) -> Int? {
        guard let gsub = tables["GSUB"], let lookupListOffset = Self.u16(data, at: gsub.offset + 8) else { return nil }
        let lookupList = gsub.offset + lookupListOffset
        guard let lookupCount = Self.u16(data, at: lookupList), index >= 0, index < lookupCount,
              let lookupOffset = Self.u16(data, at: lookupList + 2 + index * 2)
        else {
            return nil
        }
        let lookup = lookupList + lookupOffset
        guard let flag = Self.u16(data, at: lookup + 2), flag & 0x0010 != 0,
              let subtableCount = Self.u16(data, at: lookup + 4),
              let filterSet = Self.u16(data, at: lookup + 6 + subtableCount * 2)
        else {
            return nil
        }
        return filterSet
    }

    /// Walks every GSUB subtable of the lookups whose feature tag satisfies
    /// `matches`, resolving extension lookups (type 7) to their effective type,
    /// and calls `body` with each subtable's byte offset, effective type, and the
    /// lookup's flag word. The shared spine of the GSUB readers.
    private func forEachGSUBSubtable(
        matching: (String) -> Bool,
        restrictTo activeFeatures: Set<Int>? = nil,
        _ body: (Int, Int, Int) -> Void
    ) {
        guard let gsub = tables["GSUB"] else { return }
        let base = gsub.offset
        guard let featureListOffset = Self.u16(data, at: base + 6) else { return }
        let featureList = base + featureListOffset

        var lookupIndices: Set<Int> = []
        if let featureCount = Self.u16(data, at: featureList) {
            for featureIndex in 0 ..< featureCount {
                // When a script's active feature set is given, gather only the
                // records that set selects; otherwise gather by tag across the
                // whole feature list (the script-agnostic fallback).
                if let activeFeatures, !activeFeatures.contains(featureIndex) { continue }
                let record = featureList + 2 + featureIndex * 6
                guard matching(Self.tag(data, at: record) ?? ""),
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
        for index in lookupIndices.sorted() {
            forEachGSUBLookupSubtable(at: index, body)
        }
    }

    /// Walks the subtables of one GSUB lookup, addressed by its index in the
    /// lookup list, resolving extension lookups (type 7). Used both for a
    /// feature's own lookups and for the nested lookups a chaining rule references.
    /// `body` receives the subtable offset, effective type, and the lookup flag.
    private func forEachGSUBLookupSubtable(at index: Int, _ body: (Int, Int, Int) -> Void) {
        guard let gsub = tables["GSUB"], let lookupListOffset = Self.u16(data, at: gsub.offset + 8) else { return }
        let lookupList = gsub.offset + lookupListOffset
        guard let lookupCount = Self.u16(data, at: lookupList), index >= 0, index < lookupCount,
              let lookupOffset = Self.u16(data, at: lookupList + 2 + index * 2)
        else {
            return
        }
        let lookup = lookupList + lookupOffset
        guard let lookupType = Self.u16(data, at: lookup),
              let lookupFlag = Self.u16(data, at: lookup + 2),
              let subtableCount = Self.u16(data, at: lookup + 4)
        else {
            return
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
            body(subtable, effectiveType, lookupFlag)
        }
    }

    /// Decodes a GSUB ChainContextSubstFormat3 (type 6, format 3) subtable: three
    /// coverage sequences (backtrack, input, lookahead) and the sequence-lookup
    /// records that name nested lookups to apply. Each nested lookup is resolved;
    /// its type-1 single substitutions become the rule's actions. Formats 1 and 2
    /// are ignored.
    private func parseChainContext(subtable: Int, ignoreMarks: Bool, into result: inout [ChainingSubstitution]) {
        guard Self.u16(data, at: subtable) == 3 else { return }
        var cursor = subtable + 2
        guard let backtrack = readCoverageSequence(at: &cursor, subtableBase: subtable),
              let input = readCoverageSequence(at: &cursor, subtableBase: subtable),
              let lookahead = readCoverageSequence(at: &cursor, subtableBase: subtable),
              let recordCount = Self.u16(data, at: cursor)
        else {
            return
        }
        cursor += 2
        var actions: [ChainingSubstitution.Action] = []
        for _ in 0 ..< recordCount {
            guard let sequenceIndex = Self.u16(data, at: cursor),
                  let lookupIndex = Self.u16(data, at: cursor + 2)
            else {
                break
            }
            cursor += 4
            var mapping: [Int: Int] = [:]
            forEachGSUBLookupSubtable(at: lookupIndex) { nested, type, _ in
                if type == 1 {
                    parseSingleSubst(subtable: nested, into: &mapping)
                }
            }
            if !mapping.isEmpty {
                actions.append(.init(sequenceIndex: sequenceIndex, mapping: mapping))
            }
        }
        guard !actions.isEmpty else { return }
        result.append(.init(backtrack: backtrack, input: input, lookahead: lookahead, actions: actions, ignoreMarks: ignoreMarks))
    }

    /// Decodes a GSUB ContextSubstFormat3 (type 5, format 3) subtable: an input
    /// coverage sequence and the nested lookup records to apply, with neither
    /// backtrack nor lookahead. It is the chaining rule's simpler sibling, so it is
    /// represented as a ``ChainingSubstitution`` with empty backtrack and lookahead
    /// and matched by the same shaper logic. Nested type-1 single substitutions
    /// become the rule's actions; formats 1 and 2 are ignored, as for chaining.
    private func parseContext(subtable: Int, ignoreMarks: Bool, into result: inout [ChainingSubstitution]) {
        guard Self.u16(data, at: subtable) == 3,
              let glyphCount = Self.u16(data, at: subtable + 2),
              let recordCount = Self.u16(data, at: subtable + 4)
        else {
            return
        }
        var cursor = subtable + 6
        var input: [Set<Int>] = []
        for _ in 0 ..< glyphCount {
            guard let coverageOffset = Self.u16(data, at: cursor),
                  let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
            else {
                return
            }
            input.append(coverage.coveredGlyphs)
            cursor += 2
        }
        var actions: [ChainingSubstitution.Action] = []
        for _ in 0 ..< recordCount {
            guard let sequenceIndex = Self.u16(data, at: cursor),
                  let lookupIndex = Self.u16(data, at: cursor + 2)
            else {
                break
            }
            cursor += 4
            var mapping: [Int: Int] = [:]
            forEachGSUBLookupSubtable(at: lookupIndex) { nested, type, _ in
                if type == 1 {
                    parseSingleSubst(subtable: nested, into: &mapping)
                }
            }
            if !mapping.isEmpty {
                actions.append(.init(sequenceIndex: sequenceIndex, mapping: mapping))
            }
        }
        guard !actions.isEmpty else { return }
        result.append(.init(backtrack: [], input: input, lookahead: [], actions: actions, ignoreMarks: ignoreMarks))
    }

    /// Reads a count-prefixed list of coverage-table offsets (each relative to
    /// `subtable`'s containing chain-context subtable) into glyph sets, advancing
    /// `cursor` past the list. `cursor` starts at the count field.
    private func readCoverageSequence(at cursor: inout Int, subtableBase: Int) -> [Set<Int>]? {
        guard let count = Self.u16(data, at: cursor) else { return nil }
        cursor += 2
        var sequence: [Set<Int>] = []
        for _ in 0 ..< count {
            guard let coverageOffset = Self.u16(data, at: cursor),
                  let coverage = OpenTypeCoverage(data: data, offset: subtableBase + coverageOffset)
            else {
                return nil
            }
            sequence.append(coverage.coveredGlyphs)
            cursor += 2
        }
        return sequence
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

    /// Decodes a GSUB subtable whose Format 1 layout is a Coverage table followed
    /// by a count-prefixed list of offsets, each pointing at a count-prefixed
    /// glyph array. Multiple Substitution (type 2, where the array is an ordered
    /// replacement Sequence) and Alternate Substitution (type 3, where the array
    /// is an AlternateSet) share this exact on-disk shape, so one decoder serves
    /// both and the caller's lookup type fixes the meaning. The covered glyph at
    /// coverage index i takes the i-th list. A glyph that maps to an empty list is
    /// kept as an empty array (a type-2 deletion); the shaping tier decides what
    /// an empty expansion means. (OpenType GSUB: MultipleSubstFormat1 /
    /// AlternateSubstFormat1.)
    private func parseSequenceSubst(subtable: Int, into result: inout [Int: [Int]]) {
        guard Self.u16(data, at: subtable) == 1,
              let coverageOffset = Self.u16(data, at: subtable + 2),
              let listCount = Self.u16(data, at: subtable + 4),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
        else {
            return
        }
        for listIndex in 0 ..< listCount {
            guard let glyph = coverage.glyph(atIndex: listIndex),
                  let listOffset = Self.u16(data, at: subtable + 6 + listIndex * 2)
            else {
                continue
            }
            let list = subtable + listOffset
            guard let glyphCount = Self.u16(data, at: list) else { continue }
            var substitutes: [Int] = []
            substitutes.reserveCapacity(glyphCount)
            var valid = true
            for glyphIndex in 0 ..< glyphCount {
                guard let substitute = Self.u16(data, at: list + 2 + glyphIndex * 2) else {
                    valid = false
                    break
                }
                substitutes.append(substitute)
            }
            if valid {
                result[glyph] = substitutes
            }
        }
    }

    /// The font's GPOS single positioning adjustments (lookup type 1) under
    /// `feature`: each covered glyph maps to the placement shift and advance change
    /// the font specifies for it, in font units. Extension lookups (type 9) are
    /// resolved. Empty when the font carries no single positioning for the feature.
    /// (OpenType GPOS: Lookup Type 1, "Single Adjustment Positioning Subtable",
    /// formats 1 and 2.)
    public func singleAdjustments(feature: String, restrictTo activeFeatures: Set<Int>? = nil) -> [Int: GlyphAdjustment] {
        var result: [Int: GlyphAdjustment] = [:]
        forEachGPOSSubtable(feature: feature, restrictTo: activeFeatures) { subtable, effectiveType in
            if effectiveType == 1 {
                parseSinglePos(subtable: subtable, into: &result)
            }
        }
        return result
    }

    /// Decodes a GPOS SinglePos subtable. Format 1 applies one value record to
    /// every covered glyph; format 2 lists a value record per covered glyph, in
    /// coverage order. The value record's fields appear in the fixed order
    /// xPlacement, yPlacement, xAdvance, yAdvance (then device/variation offsets,
    /// which are sized but not applied), each present only when its `valueFormat`
    /// bit is set.
    private func parseSinglePos(subtable: Int, into result: inout [Int: GlyphAdjustment]) {
        guard let format = Self.u16(data, at: subtable),
              let coverageOffset = Self.u16(data, at: subtable + 2),
              let valueFormat = Self.u16(data, at: subtable + 4),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
        else {
            return
        }
        if format == 1 {
            let adjustment = readValueRecord(at: subtable + 6, valueFormat: valueFormat)
            guard !adjustment.isZero else { return }
            for glyph in coverage.coveredGlyphs {
                result[glyph] = adjustment
            }
        } else if format == 2 {
            guard let valueCount = Self.u16(data, at: subtable + 6) else { return }
            let recordSize = (valueFormat & 0xFF).nonzeroBitCount * 2
            for index in 0 ..< valueCount {
                guard let glyph = coverage.glyph(atIndex: index) else { continue }
                let adjustment = readValueRecord(at: subtable + 8 + index * recordSize, valueFormat: valueFormat)
                if !adjustment.isZero {
                    result[glyph] = adjustment
                }
            }
        }
    }

    /// Reads a GPOS ValueRecord into a ``GlyphAdjustment``, taking only the
    /// placement and advance fields. Each field is a 2-byte signed value present
    /// only when its `valueFormat` bit is set, and they are packed in the fixed
    /// order below, so reading sequentially when a bit is set lands on the right
    /// bytes. Device and variation fields (bits 0x0010 and up) are not applied.
    private func readValueRecord(at offset: Int, valueFormat: Int) -> GlyphAdjustment {
        var cursor = offset
        func field(_ bit: Int) -> Int {
            guard valueFormat & bit != 0 else { return 0 }
            let value = Self.i16(data, at: cursor) ?? 0
            cursor += 2
            return value
        }
        let xPlacement = field(0x0001)
        let yPlacement = field(0x0002)
        let xAdvance = field(0x0004)
        let yAdvance = field(0x0008)
        return GlyphAdjustment(xPlacement: xPlacement, yPlacement: yPlacement, xAdvance: xAdvance, yAdvance: yAdvance)
    }

    /// The font's GPOS contextual positioning rules under `feature`: chained
    /// (lookup type 8) and plain contextual (type 7) positioning, format 3, with
    /// nested type-1 single-adjustment lookups resolved into per-position
    /// adjustments. Empty when the font carries none. Extension lookups (type 9)
    /// are resolved. The shaping tier applies these during positioning.
    public func contextualPositioning(feature: String, restrictTo activeFeatures: Set<Int>? = nil) -> [ContextualPositioning] {
        var result: [ContextualPositioning] = []
        forEachGPOSSubtable(feature: feature, restrictTo: activeFeatures) { subtable, effectiveType in
            if effectiveType == 8 {
                parseContextPositioning(subtable: subtable, chaining: true, into: &result)
            } else if effectiveType == 7 {
                parseContextPositioning(subtable: subtable, chaining: false, into: &result)
            }
        }
        return result
    }

    /// Decodes a GPOS contextual (type 7) or chained contextual (type 8) subtable
    /// into ``ContextualPositioning`` values, across all three OpenType formats:
    /// format 1 lists explicit glyph sequences, format 2 class sequences (expanded
    /// here through the subtable's class definitions), and format 3 coverage
    /// sequences. The positioning analogue of ``parseContextRecords``; each nested
    /// positioning lookup's type-1 single adjustments are resolved into the rule's
    /// actions. `chaining` selects whether backtrack and lookahead are present.
    private func parseContextPositioning(subtable: Int, chaining: Bool, into result: inout [ContextualPositioning]) {
        switch Self.u16(data, at: subtable) {
        case 1: parseContextPosFormat1(subtable: subtable, chaining: chaining, into: &result)
        case 2: parseContextPosFormat2(subtable: subtable, chaining: chaining, into: &result)
        case 3: parseContextPosFormat3(subtable: subtable, chaining: chaining, into: &result)
        default: break
        }
    }

    /// Decodes a type-7/8 contextual positioning subtable in format 3 (coverage
    /// sequences). A chained subtable lists its record count last, after the
    /// lookahead; a plain context subtable lists it right after the input glyph
    /// count, before the input coverages.
    private func parseContextPosFormat3(subtable: Int, chaining: Bool, into result: inout [ContextualPositioning]) {
        if chaining {
            var cursor = subtable + 2
            guard let backtrack = readCoverageSequence(at: &cursor, subtableBase: subtable),
                  let input = readCoverageSequence(at: &cursor, subtableBase: subtable),
                  let lookahead = readCoverageSequence(at: &cursor, subtableBase: subtable),
                  let recordCount = Self.u16(data, at: cursor)
            else {
                return
            }
            cursor += 2
            let actions = readPositioningActions(at: &cursor, recordCount: recordCount)
            guard !actions.isEmpty else { return }
            result.append(.init(backtrack: backtrack, input: input, lookahead: lookahead, actions: actions))
        } else {
            guard let glyphCount = Self.u16(data, at: subtable + 2),
                  let recordCount = Self.u16(data, at: subtable + 4)
            else {
                return
            }
            var cursor = subtable + 6
            var input: [Set<Int>] = []
            for _ in 0 ..< glyphCount {
                guard let coverageOffset = Self.u16(data, at: cursor),
                      let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
                else {
                    return
                }
                input.append(coverage.coveredGlyphs)
                cursor += 2
            }
            let actions = readPositioningActions(at: &cursor, recordCount: recordCount)
            guard !actions.isEmpty else { return }
            result.append(.init(backtrack: [], input: input, lookahead: [], actions: actions))
        }
    }

    /// Decodes a type-7/8 contextual positioning subtable in format 1 (a coverage
    /// selects a rule set per first-input glyph; each rule lists explicit glyph ids
    /// for the rest of the input, and the backtrack and lookahead when chaining).
    private func parseContextPosFormat1(subtable: Int, chaining: Bool, into result: inout [ContextualPositioning]) {
        guard let coverageOffset = Self.u16(data, at: subtable + 2),
              let ruleSetCount = Self.u16(data, at: subtable + 4),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
        else {
            return
        }
        for ruleSetIndex in 0 ..< ruleSetCount {
            guard let firstGlyph = coverage.glyph(atIndex: ruleSetIndex),
                  let ruleSetOffset = Self.u16(data, at: subtable + 6 + ruleSetIndex * 2), ruleSetOffset != 0
            else {
                continue
            }
            let ruleSet = subtable + ruleSetOffset
            guard let ruleCount = Self.u16(data, at: ruleSet) else { continue }
            for ruleIndex in 0 ..< ruleCount {
                guard let ruleOffset = Self.u16(data, at: ruleSet + 2 + ruleIndex * 2), ruleOffset != 0 else { continue }
                var cursor = ruleSet + ruleOffset
                var backtrack: [Set<Int>] = []
                if chaining {
                    guard let glyphs = readGlyphSequence(at: &cursor) else { continue }
                    backtrack = glyphs.map { [$0] }
                }
                guard let inputCount = Self.u16(data, at: cursor) else { continue }
                cursor += 2
                var recordCount = 0
                if !chaining {
                    guard let count = Self.u16(data, at: cursor) else { continue }
                    recordCount = count
                    cursor += 2
                }
                var input: [Set<Int>] = [[firstGlyph]]
                var valid = true
                for _ in 0 ..< max(0, inputCount - 1) {
                    guard let glyph = Self.u16(data, at: cursor) else { valid = false
                        break
                    }
                    input.append([glyph])
                    cursor += 2
                }
                guard valid else { continue }
                var lookahead: [Set<Int>] = []
                if chaining {
                    guard let glyphs = readGlyphSequence(at: &cursor) else { continue }
                    lookahead = glyphs.map { [$0] }
                    guard let count = Self.u16(data, at: cursor) else { continue }
                    recordCount = count
                    cursor += 2
                }
                let actions = readPositioningActions(at: &cursor, recordCount: recordCount)
                guard !actions.isEmpty else { continue }
                result.append(.init(backtrack: backtrack, input: input, lookahead: lookahead, actions: actions))
            }
        }
    }

    /// Decodes a type-7/8 contextual positioning subtable in format 2 (class
    /// definitions classify the glyphs; a rule set is selected per first-input
    /// class, and each rule lists class values for the rest of the input, and the
    /// backtrack and lookahead when chaining). Each class is expanded to its glyph
    /// set so the rule matches like the other formats.
    private func parseContextPosFormat2(subtable: Int, chaining: Bool, into result: inout [ContextualPositioning]) {
        guard let coverageOffset = Self.u16(data, at: subtable + 2),
              OpenTypeCoverage(data: data, offset: subtable + coverageOffset) != nil
        else {
            return
        }
        let backtrackSets: [Int: Set<Int>]
        let inputSets: [Int: Set<Int>]
        let lookaheadSets: [Int: Set<Int>]
        var cursor = subtable + 4
        if chaining {
            guard let backOffset = Self.u16(data, at: cursor),
                  let inputOffset = Self.u16(data, at: cursor + 2),
                  let aheadOffset = Self.u16(data, at: cursor + 4)
            else {
                return
            }
            backtrackSets = gsubClassGlyphSets(atOffset: backOffset, subtableBase: subtable)
            inputSets = gsubClassGlyphSets(atOffset: inputOffset, subtableBase: subtable)
            lookaheadSets = gsubClassGlyphSets(atOffset: aheadOffset, subtableBase: subtable)
            cursor += 6
        } else {
            guard let classDefOffset = Self.u16(data, at: cursor) else { return }
            let sets = gsubClassGlyphSets(atOffset: classDefOffset, subtableBase: subtable)
            backtrackSets = sets
            inputSets = sets
            lookaheadSets = sets
            cursor += 2
        }
        guard let ruleSetCount = Self.u16(data, at: cursor) else { return }
        cursor += 2
        let ruleSetBase = cursor
        for ruleSetIndex in 0 ..< ruleSetCount {
            guard let ruleSetOffset = Self.u16(data, at: ruleSetBase + ruleSetIndex * 2), ruleSetOffset != 0 else { continue }
            let ruleSet = subtable + ruleSetOffset
            guard let ruleCount = Self.u16(data, at: ruleSet) else { continue }
            for ruleIndex in 0 ..< ruleCount {
                guard let ruleOffset = Self.u16(data, at: ruleSet + 2 + ruleIndex * 2), ruleOffset != 0 else { continue }
                var rule = ruleSet + ruleOffset
                var backtrack: [Set<Int>] = []
                if chaining {
                    guard let classes = readGlyphSequence(at: &rule) else { continue }
                    backtrack = classes.map { backtrackSets[$0] ?? [] }
                }
                guard let inputCount = Self.u16(data, at: rule) else { continue }
                rule += 2
                var recordCount = 0
                if !chaining {
                    guard let count = Self.u16(data, at: rule) else { continue }
                    recordCount = count
                    rule += 2
                }
                var input: [Set<Int>] = [inputSets[ruleSetIndex] ?? []]
                var valid = true
                for _ in 0 ..< max(0, inputCount - 1) {
                    guard let value = Self.u16(data, at: rule) else { valid = false
                        break
                    }
                    input.append(inputSets[value] ?? [])
                    rule += 2
                }
                guard valid else { continue }
                var lookahead: [Set<Int>] = []
                if chaining {
                    guard let classes = readGlyphSequence(at: &rule) else { continue }
                    lookahead = classes.map { lookaheadSets[$0] ?? [] }
                    guard let count = Self.u16(data, at: rule) else { continue }
                    recordCount = count
                    rule += 2
                }
                let actions = readPositioningActions(at: &rule, recordCount: recordCount)
                guard !actions.isEmpty else { continue }
                result.append(.init(backtrack: backtrack, input: input, lookahead: lookahead, actions: actions))
            }
        }
    }

    /// Walks the subtables of one GPOS lookup, addressed by its index in the lookup
    /// list, resolving extension lookups (type 9). Used to resolve the nested
    /// lookups a contextual positioning rule references. `body` receives the
    /// subtable offset and effective type.
    private func forEachGPOSLookupSubtable(at index: Int, _ body: (Int, Int) -> Void) {
        guard let gpos = tables["GPOS"], let lookupListOffset = Self.u16(data, at: gpos.offset + 8) else { return }
        let lookupList = gpos.offset + lookupListOffset
        guard let lookupCount = Self.u16(data, at: lookupList), index >= 0, index < lookupCount,
              let lookupOffset = Self.u16(data, at: lookupList + 2 + index * 2)
        else {
            return
        }
        let lookup = lookupList + lookupOffset
        guard let lookupType = Self.u16(data, at: lookup),
              let subtableCount = Self.u16(data, at: lookup + 4)
        else {
            return
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
            body(subtable, effectiveType)
        }
    }

    /// Reads `recordCount` sequence-lookup records starting at `cursor` (each a
    /// sequence index and a lookup-list index), resolving each referenced GPOS
    /// lookup's type-1 single adjustments into an action. Advances `cursor` past
    /// the records.
    private func readPositioningActions(at cursor: inout Int, recordCount: Int) -> [ContextualPositioning.Action] {
        var actions: [ContextualPositioning.Action] = []
        for _ in 0 ..< recordCount {
            guard let sequenceIndex = Self.u16(data, at: cursor),
                  let lookupIndex = Self.u16(data, at: cursor + 2)
            else {
                break
            }
            cursor += 4
            var adjustments: [Int: GlyphAdjustment] = [:]
            forEachGPOSLookupSubtable(at: lookupIndex) { nested, type in
                if type == 1 {
                    parseSinglePos(subtable: nested, into: &adjustments)
                }
            }
            if !adjustments.isEmpty {
                actions.append(.init(sequenceIndex: sequenceIndex, adjustments: adjustments))
            }
        }
        return actions
    }

    /// The font's mark-to-base attachment (GPOS lookup type 4), for the shaping tier
    /// to seat combining marks over their bases (Arabic vowel marks, for example).
    /// Gathers the general `mark` feature together with the Indic above-base (`abvm`)
    /// and below-base (`blwm`) mark features, which seat a Devanagari reph or an
    /// i/u-matra over its consonant; those features exist only in Indic fonts, so they
    /// are a no-op elsewhere. Extension lookups (type 9) are resolved. Empty when the
    /// font carries no mark positioning.
    public func markAttachment(variations: [String: Double] = [:]) -> MarkAttachment {
        collectMarkAttachment(features: ["mark", "abvm", "blwm"], lookupType: 4, normalized: variations.isEmpty ? nil : normalizedVariationCoordinates(variations))
    }

    /// The font's GPOS mark-to-mark attachment (the `mkmk` feature, lookup type
    /// 6): where a combining mark sits over the mark that precedes it, so a
    /// second diacritic stacks above the first (an Arabic vowel over a shadda,
    /// stacked tone and vowel marks). The returned ``MarkAttachment`` treats the
    /// attaching mark as its `marks` and the preceding mark it rides on as its
    /// `bases`, so ``MarkAttachment/offset(base:mark:)`` reads the same way as
    /// for mark-to-base. Empty when the font carries no mark-to-mark attachment.
    public func markMarkAttachment(variations: [String: Double] = [:]) -> MarkAttachment {
        collectMarkAttachment(features: ["mkmk"], lookupType: 6, normalized: variations.isEmpty ? nil : normalizedVariationCoordinates(variations))
    }

    /// The font's GPOS mark-to-ligature attachment (the `mark` feature, lookup type
    /// 5): per-component anchors that seat a combining mark over the right part of a
    /// ligature. Extension lookups (type 9) are resolved. Empty when the font
    /// carries no mark-to-ligature attachment.
    public func markLigatureAttachment(variations: [String: Double] = [:]) -> MarkLigatureAttachment {
        var marks: [Int: MarkAttachment.Mark] = [:]
        var ligatures: [Int: [[Int: MarkAttachment.Point]]] = [:]
        let normalized = variations.isEmpty ? nil : normalizedVariationCoordinates(variations)
        forEachGPOSSubtable(feature: "mark") { subtable, effectiveType in
            if effectiveType == 5 {
                parseMarkLigatureSubtable(subtable: subtable, normalized: normalized, marks: &marks, ligatures: &ligatures)
            }
        }
        return MarkLigatureAttachment(marks: marks, ligatures: ligatures)
    }

    /// Decodes a GPOS MarkLigPosFormat1 subtable. The mark array is identical to
    /// mark-to-base; the ligature array replaces the base array with, per ligature,
    /// a LigatureAttach of `componentCount` components, each carrying one anchor
    /// offset per mark class (0 meaning the component offers no anchor for that
    /// class). Anchor offsets in a LigatureAttach are relative to that table.
    private func parseMarkLigatureSubtable(
        subtable: Int,
        normalized: [Double]?,
        marks: inout [Int: MarkAttachment.Mark],
        ligatures: inout [Int: [[Int: MarkAttachment.Point]]]
    ) {
        guard Self.u16(data, at: subtable) == 1,
              let markCoverageOffset = Self.u16(data, at: subtable + 2),
              let ligatureCoverageOffset = Self.u16(data, at: subtable + 4),
              let markClassCount = Self.u16(data, at: subtable + 6),
              let markArrayOffset = Self.u16(data, at: subtable + 8),
              let ligatureArrayOffset = Self.u16(data, at: subtable + 10),
              let markCoverage = OpenTypeCoverage(data: data, offset: subtable + markCoverageOffset),
              let ligatureCoverage = OpenTypeCoverage(data: data, offset: subtable + ligatureCoverageOffset)
        else {
            return
        }

        let markArray = subtable + markArrayOffset
        if let markCount = Self.u16(data, at: markArray) {
            for index in 0 ..< markCount {
                let record = markArray + 2 + index * 4
                guard let markGlyph = markCoverage.glyph(atIndex: index),
                      let markClass = Self.u16(data, at: record),
                      let anchorOffset = Self.u16(data, at: record + 2),
                      let anchor = anchor(at: markArray + anchorOffset, normalized: normalized)
                else {
                    continue
                }
                marks[markGlyph] = MarkAttachment.Mark(markClass: markClass, anchor: anchor)
            }
        }

        let ligatureArray = subtable + ligatureArrayOffset
        guard let ligatureCount = Self.u16(data, at: ligatureArray) else { return }
        for index in 0 ..< ligatureCount {
            guard let ligatureGlyph = ligatureCoverage.glyph(atIndex: index),
                  let attachOffset = Self.u16(data, at: ligatureArray + 2 + index * 2)
            else {
                continue
            }
            let attach = ligatureArray + attachOffset
            guard let componentCount = Self.u16(data, at: attach) else { continue }
            var components: [[Int: MarkAttachment.Point]] = []
            for component in 0 ..< componentCount {
                var classAnchors: [Int: MarkAttachment.Point] = [:]
                for markClass in 0 ..< markClassCount {
                    let offsetPosition = attach + 2 + (component * markClassCount + markClass) * 2
                    guard let anchorOffset = Self.u16(data, at: offsetPosition), anchorOffset != 0,
                          let anchor = anchor(at: attach + anchorOffset, normalized: normalized)
                    else {
                        continue
                    }
                    classAnchors[markClass] = anchor
                }
                components.append(classAnchors)
            }
            ligatures[ligatureGlyph] = components
        }
    }

    /// The font's GPOS cursive attachment (the `curs` feature, lookup type 3):
    /// the entry and exit anchors that join glyphs along a flowing baseline, so a
    /// connected script links one glyph's exit to the next glyph's entry. Empty
    /// when the font carries no cursive attachment. PureDraw parses the GPOS
    /// table; this forwards the typed result for the shaper to connect glyphs.
    public func cursiveAttachment(restrictTo activeFeatures: Set<Int>? = nil, variations: [String: Double] = [:]) -> CursiveAttachment {
        var entries: [Int: CursiveAttachment.Point] = [:]
        var exits: [Int: CursiveAttachment.Point] = [:]
        let normalized = variations.isEmpty ? nil : normalizedVariationCoordinates(variations)
        forEachGPOSSubtable(feature: "curs", restrictTo: activeFeatures) { subtable, effectiveType in
            if effectiveType == 3 {
                parseCursivePos(subtable: subtable, normalized: normalized, entries: &entries, exits: &exits)
            }
        }
        return CursiveAttachment(entries: entries, exits: exits)
    }

    /// Gathers the anchor data of a GPOS mark-attachment feature into a typed
    /// ``MarkAttachment``. `lookupType` is 4 for mark-to-base (the `mark`
    /// feature) and 6 for mark-to-mark (the `mkmk` feature); the two share the
    /// same subtable layout, so one parser serves both.
    private func collectMarkAttachment(features wanted: [String], lookupType wantedType: Int, normalized: [Double]?) -> MarkAttachment {
        var marks: [Int: [MarkAttachment.Mark]] = [:]
        var bases: [Int: [Int: MarkAttachment.Point]] = [:]
        // Mark classes are local to each subtable: class 0 in one mark lookup is a
        // different class than class 0 in the next, and the BaseArray that pairs
        // with it is the matching subtable's. Merging every subtable into one map
        // keyed by the raw class would collide the classes, so a base covered by
        // two lookups (common in Nastaliq, where most bases are) would take the
        // wrong subtable's anchor. Give each subtable a disjoint class range by
        // offsetting its classes past every class already seen; the mark and the
        // base anchors of one subtable then keep their pairing across the merge. The
        // offset carries across the features too, so the above-base (`abvm`) and
        // below-base (`blwm`) Indic mark lookups merge with `mark` without colliding.
        var classOffset = 0
        for feature in wanted {
            forEachGPOSSubtable(feature: feature) { subtable, effectiveType in
                if effectiveType == wantedType {
                    classOffset += parseMarkAnchorSubtable(subtable: subtable, classOffset: classOffset, normalized: normalized, marks: &marks, bases: &bases)
                }
            }
        }
        return MarkAttachment(marks: marks, bases: bases)
    }

    /// Walks every GPOS subtable of the lookups a feature references, resolving
    /// extension lookups (type 9) to their effective type, and calls `body` with
    /// each subtable's byte offset and effective lookup type. The shared spine of
    /// the GPOS readers (mark, mark-to-mark, cursive).
    private func forEachGPOSSubtable(feature wanted: String, restrictTo activeFeatures: Set<Int>? = nil, _ body: (Int, Int) -> Void) {
        guard let gpos = tables["GPOS"] else { return }
        let base = gpos.offset
        guard let featureListOffset = Self.u16(data, at: base + 6),
              let lookupListOffset = Self.u16(data, at: base + 8)
        else {
            return
        }
        let featureList = base + featureListOffset
        let lookupList = base + lookupListOffset

        var lookupIndices: Set<Int> = []
        if let featureCount = Self.u16(data, at: featureList) {
            for featureIndex in 0 ..< featureCount {
                // When a script's active feature set is given, gather only the
                // records that set selects; otherwise gather by tag (the
                // script-agnostic fallback), as for GSUB.
                if let activeFeatures, !activeFeatures.contains(featureIndex) { continue }
                let record = featureList + 2 + featureIndex * 6
                guard Self.tag(data, at: record) == wanted,
                      let featureOffset = Self.u16(data, at: record + 4)
                else {
                    continue
                }
                let feature = featureList + featureOffset
                guard let lookupIndexCount = Self.u16(data, at: feature + 2) else { continue }
                for lookupIndex in 0 ..< lookupIndexCount {
                    if let index = Self.u16(data, at: feature + 4 + lookupIndex * 2) {
                        lookupIndices.insert(index)
                    }
                }
            }
        }

        guard let lookupCount = Self.u16(data, at: lookupList) else { return }
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
                body(subtable, effectiveType)
            }
        }
    }

    /// Decodes a GPOS CursivePos (type 3) subtable into the per-glyph entry and
    /// exit anchors. An entry-exit record with a null (zero) anchor offset leaves
    /// that side absent.
    private func parseCursivePos(
        subtable: Int,
        normalized: [Double]?,
        entries: inout [Int: CursiveAttachment.Point],
        exits: inout [Int: CursiveAttachment.Point]
    ) {
        guard Self.u16(data, at: subtable) == 1,
              let coverageOffset = Self.u16(data, at: subtable + 2),
              let entryExitCount = Self.u16(data, at: subtable + 4),
              let coverage = OpenTypeCoverage(data: data, offset: subtable + coverageOffset)
        else {
            return
        }
        for index in 0 ..< entryExitCount {
            guard let glyph = coverage.glyph(atIndex: index) else { continue }
            let record = subtable + 6 + index * 4
            if let entryOffset = Self.u16(data, at: record), entryOffset != 0,
               let point = anchorCoordinates(at: subtable + entryOffset, normalized: normalized)
            {
                entries[glyph] = CursiveAttachment.Point(x: point.x, y: point.y)
            }
            if let exitOffset = Self.u16(data, at: record + 2), exitOffset != 0,
               let point = anchorCoordinates(at: subtable + exitOffset, normalized: normalized)
            {
                exits[glyph] = CursiveAttachment.Point(x: point.x, y: point.y)
            }
        }
    }

    /// Decodes a GPOS mark-attachment subtable (MarkBasePos type 4 or MarkMarkPos
    /// type 6, which share format 1) into the mark and base anchor maps. For
    /// mark-to-mark the "base" array is the Mark2Array of preceding marks. Anchor
    /// coordinates are read from all anchor formats (1, 2, and 3); the device and
    /// contour-point refinements of formats 2 and 3 are not applied.
    /// Decodes one GPOS MarkBasePosFormat1 (or the structurally identical
    /// MarkMarkPosFormat1) subtable into the shared `marks` and `bases` maps, with
    /// each class shifted by `classOffset` so this subtable's classes do not
    /// collide with another's. A mark seen in a later subtable overwrites the
    /// earlier (a mark belongs to one subtable in practice); a base's anchors are
    /// merged, so a base covered by several subtables keeps each subtable's anchor
    /// under that subtable's offset class. Returns this subtable's class count, the
    /// amount to advance `classOffset` by for the next.
    @discardableResult
    private func parseMarkAnchorSubtable(
        subtable: Int,
        classOffset: Int,
        normalized: [Double]?,
        marks: inout [Int: [MarkAttachment.Mark]],
        bases: inout [Int: [Int: MarkAttachment.Point]]
    ) -> Int {
        guard Self.u16(data, at: subtable) == 1,
              let markCoverageOffset = Self.u16(data, at: subtable + 2),
              let baseCoverageOffset = Self.u16(data, at: subtable + 4),
              let markClassCount = Self.u16(data, at: subtable + 6),
              let markArrayOffset = Self.u16(data, at: subtable + 8),
              let baseArrayOffset = Self.u16(data, at: subtable + 10),
              let markCoverage = OpenTypeCoverage(data: data, offset: subtable + markCoverageOffset),
              let baseCoverage = OpenTypeCoverage(data: data, offset: subtable + baseCoverageOffset)
        else {
            return 0
        }

        let markArray = subtable + markArrayOffset
        if let markCount = Self.u16(data, at: markArray) {
            for index in 0 ..< markCount {
                let record = markArray + 2 + index * 4
                guard let markGlyph = markCoverage.glyph(atIndex: index),
                      let markClass = Self.u16(data, at: record),
                      let anchorOffset = Self.u16(data, at: record + 2),
                      let anchor = anchor(at: markArray + anchorOffset, normalized: normalized)
                else {
                    continue
                }
                marks[markGlyph, default: []].append(MarkAttachment.Mark(markClass: markClass + classOffset, anchor: anchor))
            }
        }

        let baseArray = subtable + baseArrayOffset
        if let baseCount = Self.u16(data, at: baseArray) {
            for index in 0 ..< baseCount {
                guard let baseGlyph = baseCoverage.glyph(atIndex: index) else { continue }
                for markClass in 0 ..< markClassCount {
                    let offsetPosition = baseArray + 2 + (index * markClassCount + markClass) * 2
                    guard let anchorOffset = Self.u16(data, at: offsetPosition), anchorOffset != 0,
                          let anchor = anchor(at: baseArray + anchorOffset, normalized: normalized)
                    else {
                        continue
                    }
                    bases[baseGlyph, default: [:]][markClass + classOffset] = anchor
                }
            }
        }
        return markClassCount
    }

    /// Reads an Anchor table's coordinates. Formats 1, 2, and 3 store the x and y
    /// at the same offsets; the format-1/2 point-index refinement is ignored. For
    /// format 3 at a variation instance (`normalized` non-nil), the x and y device
    /// tables that are VariationIndex tables contribute the instance's delta from
    /// the GDEF ItemVariationStore, so a mark anchor shifts with the axis the way
    /// Core Text places it. The hinting Device tables (delta formats 1-3) are
    /// ignored, as before.
    private func anchorCoordinates(at offset: Int, normalized: [Double]?) -> (x: Int, y: Int)? {
        guard let format = Self.u16(data, at: offset),
              let x = Self.i16(data, at: offset + 2),
              let y = Self.i16(data, at: offset + 4)
        else {
            return nil
        }
        guard format == 3, let normalized, let store = gdefItemVariationStoreOffset else {
            return (x, y)
        }
        let dx = Self.u16(data, at: offset + 6).flatMap { $0 == 0 ? nil : variationIndexDelta(at: offset + $0, store: store, normalized: normalized) } ?? 0
        let dy = Self.u16(data, at: offset + 8).flatMap { $0 == 0 ? nil : variationIndexDelta(at: offset + $0, store: store, normalized: normalized) } ?? 0
        return (x + dx, y + dy)
    }

    /// An Anchor table's coordinates as a ``MarkAttachment/Point``, at the variation
    /// instance `normalized` (nil for a static font or the default instance).
    private func anchor(at offset: Int, normalized: [Double]?) -> MarkAttachment.Point? {
        guard let point = anchorCoordinates(at: offset, normalized: normalized) else { return nil }
        return MarkAttachment.Point(x: point.x, y: point.y)
    }

    /// The byte offset of the GDEF ItemVariationStore (GDEF table version 1.3 and
    /// later), or nil when the font's GDEF carries none. GPOS anchors and value
    /// records reference it by VariationIndex to vary with the axes.
    private var gdefItemVariationStoreOffset: Int? {
        guard let gdef = tables["GDEF"],
              let minor = Self.u16(data, at: gdef.offset + 2), minor >= 3,
              let storeOffset = Self.u32(data, at: gdef.offset + 14), storeOffset != 0
        else {
            return nil
        }
        return gdef.offset + storeOffset
    }

    /// The font-unit delta a VariationIndex table at `offset` contributes at the
    /// instance `normalized`: it names an ItemVariationStore item by (outer, inner)
    /// index, interpolated through `store`. Zero when the table is an ordinary
    /// hinting Device table (delta format other than 0x8000).
    private func variationIndexDelta(at offset: Int, store: Int, normalized: [Double]) -> Int {
        guard Self.u16(data, at: offset + 4) == 0x8000,
              let outer = Self.u16(data, at: offset),
              let inner = Self.u16(data, at: offset + 2)
        else {
            return 0
        }
        return Int(itemVariationStoreDelta(at: store, outer: outer, inner: inner, normalized: normalized).rounded())
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

    /// The horizontal advance of `index` in font units at the variation instance
    /// `variations` (axis tag to user value): the static `hmtx` advance plus the
    /// `HVAR` delta for the instance. Equal to ``advanceWidth(forGlyph:)`` for a
    /// static font or one without `HVAR`. The advance Core Text uses for a
    /// variable-font instance, which can differ from `hmtx` even at the default
    /// position when the font's `hmtx` is not its default-instance baseline.
    public func advanceWidth(forGlyph index: Int, variations: [String: Double]) -> Double {
        let base = advanceWidth(forGlyph: index)
        guard let normalized = normalizedVariationCoordinates(variations) else { return base }
        return base + hvarAdvanceDelta(glyph: index, normalized: normalized)
    }

    /// The `HVAR` advance-width delta for `glyph` at `normalized` axis coordinates,
    /// in font units. The advance DeltaSetIndexMap maps the glyph to an item in the
    /// ItemVariationStore, which interpolates the delta from its variation regions.
    /// Zero when the font carries no `HVAR` table.
    private func hvarAdvanceDelta(glyph: Int, normalized: [Double]) -> Double {
        guard let hvar = tables["HVAR"], let ivsOffset = Self.u32(data, at: hvar.offset + 4) else { return 0 }
        let advanceMapOffset = Self.u32(data, at: hvar.offset + 8) ?? 0
        let index = deltaSetIndex(glyph: glyph, mapOffset: advanceMapOffset == 0 ? nil : hvar.offset + advanceMapOffset)
        return itemVariationStoreDelta(at: hvar.offset + ivsOffset, outer: index.outer, inner: index.inner, normalized: normalized)
    }

    /// The (outer, inner) delta-set index for `glyph` from a DeltaSetIndexMap at
    /// `mapOffset`, or the implicit identity `(0, glyph)` when there is no map.
    private func deltaSetIndex(glyph: Int, mapOffset: Int?) -> (outer: Int, inner: Int) {
        guard let mapOffset, let format = Self.u8(data, at: mapOffset), let entryFormat = Self.u8(data, at: mapOffset + 1) else {
            return (0, glyph)
        }
        let entrySize = ((entryFormat & 0x30) >> 4) + 1
        let innerBits = (entryFormat & 0x0F) + 1
        let mapCount: Int
        let dataStart: Int
        if format == 0 {
            mapCount = Self.u16(data, at: mapOffset + 2) ?? 0
            dataStart = mapOffset + 4
        } else {
            mapCount = Self.u32(data, at: mapOffset + 2) ?? 0
            dataStart = mapOffset + 6
        }
        let entryIndex = min(glyph, mapCount - 1)
        guard entryIndex >= 0 else { return (0, glyph) }
        var entry = 0
        for byte in 0 ..< entrySize {
            guard let value = Self.u8(data, at: dataStart + entryIndex * entrySize + byte) else { return (0, glyph) }
            entry = (entry << 8) | value
        }
        return (entry >> innerBits, entry & ((1 << innerBits) - 1))
    }

    /// The interpolated delta for item `(outer, inner)` of the ItemVariationStore at
    /// `ivsOffset`, at `normalized` axis coordinates, in font units: the sum over the
    /// subtable's regions of the region scalar times that region's stored delta.
    /// (OpenType, "Item Variation Store".)
    private func itemVariationStoreDelta(at ivsOffset: Int, outer: Int, inner: Int, normalized: [Double]) -> Double {
        guard Self.u16(data, at: ivsOffset) == 1,
              let regionListOffset = Self.u32(data, at: ivsOffset + 2),
              let dataCount = Self.u16(data, at: ivsOffset + 6), outer < dataCount,
              let subtableOffset = Self.u32(data, at: ivsOffset + 8 + outer * 4)
        else {
            return 0
        }
        let regionList = ivsOffset + regionListOffset
        guard let axisCount = Self.u16(data, at: regionList), let regionCount = Self.u16(data, at: regionList + 2) else { return 0 }
        let subtable = ivsOffset + subtableOffset
        guard let itemCount = Self.u16(data, at: subtable),
              let wordDeltaCount = Self.u16(data, at: subtable + 2),
              let regionIndexCount = Self.u16(data, at: subtable + 4), inner < itemCount
        else {
            return 0
        }
        let longWords = (wordDeltaCount & 0x8000) != 0
        let wordCount = wordDeltaCount & 0x7FFF
        var regionIndices: [Int] = []
        for index in 0 ..< regionIndexCount {
            regionIndices.append(Self.u16(data, at: subtable + 6 + index * 2) ?? 0)
        }
        let rowSize = wordCount * (longWords ? 4 : 2) + (regionIndexCount - wordCount) * (longWords ? 2 : 1)
        var cursor = subtable + 6 + regionIndexCount * 2 + inner * rowSize
        var delta = 0.0
        for column in 0 ..< regionIndexCount {
            let value: Int
            if column < wordCount {
                value = (longWords ? i32(at: cursor) : Self.i16(data, at: cursor)) ?? 0
                cursor += longWords ? 4 : 2
            } else {
                value = (longWords ? Self.i16(data, at: cursor) : Self.i8(data, at: cursor)) ?? 0
                cursor += longWords ? 2 : 1
            }
            let regionIndex = regionIndices[column]
            guard regionIndex < regionCount else { continue }
            delta += regionScalar(regionList: regionList, axisCount: axisCount, region: regionIndex, normalized: normalized) * Double(value)
        }
        return delta
    }

    /// A signed 32-bit big-endian integer at `offset`, derived from the unsigned read.
    private func i32(at offset: Int) -> Int? {
        guard let value = Self.u32(data, at: offset) else { return nil }
        return value >= 0x8000_0000 ? value - 0x1_0000_0000 : value
    }

    /// The variation scalar of `region` at `normalized` coordinates: the product of
    /// the per-axis interpolation factors. A region axis with peak 0 does not
    /// participate. (OpenType, "Algorithm for interpolation of instance values".)
    private func regionScalar(regionList: Int, axisCount: Int, region: Int, normalized: [Double]) -> Double {
        let base = regionList + 4 + region * axisCount * 6
        var scalar = 1.0
        for axis in 0 ..< axisCount {
            let record = base + axis * 6
            guard let start = Self.f2dot14(data, at: record),
                  let peak = Self.f2dot14(data, at: record + 2),
                  let end = Self.f2dot14(data, at: record + 4)
            else {
                return 0
            }
            let coord = axis < normalized.count ? normalized[axis] : 0
            let factor: Double = if peak == 0 {
                1
            } else if coord < start || coord > end {
                0
            } else if coord == peak {
                1
            } else if coord < peak {
                peak > start ? (coord - start) / (peak - start) : 0
            } else {
                end > peak ? (end - coord) / (end - peak) : 0
            }
            scalar *= factor
            if scalar == 0 { break }
        }
        return scalar
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
