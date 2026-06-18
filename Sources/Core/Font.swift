//
//  Font.swift
//  PureDraw
//

import Geometry
import Validation

/// A parsed TrueType font (`.ttf`, or the first face of a `.ttc` collection).
/// Decodes `cmap` for character-to-glyph mapping and `glyf` for quadratic
/// outlines, returned as `Path` values in font units with y pointing up.
/// CFF-outlined OpenType fonts (`OTTO`) are not supported.
public struct Font: Equatable, Sendable {
    /// Font units per em square; glyph coordinates divide by this.
    public let unitsPerEm: Int
    /// Typographic ascent in font units.
    public let ascent: Double
    /// Typographic descent in font units (typically negative).
    public let descent: Double
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

    /// Equality compares the underlying font data; every parsed field is
    /// derived from it.
    public static func == (lhs: Font, rhs: Font) -> Bool {
        lhs.data == rhs.data
    }

    // MARK: - Parsing

    public init(provider: DataProvider) throws {
        try self.init(data: provider.data())
    }

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

        // Outlines come from either glyf/loca (TrueType) or a CFF table
        // (PostScript-outlined OpenType).
        var parsedCFF: CFFFont?
        if let cffTable = tableDirectory["CFF "] {
            parsedCFF = CFFFont(data: bytes, offset: cffTable.offset, length: cffTable.length)
            guard parsedCFF != nil else {
                throw Self.error("invalid CFF table")
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

    // MARK: - Outlines

    /// The glyph outline as a path in font units (y up), or `nil` for empty
    /// or out-of-range glyphs.
    public func outline(forGlyph index: Int) -> Path? {
        if let cff {
            return cff.outline(glyphIndex: index)
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
        var cursor = glyphOffset + 10
        var path = Path()

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

            var transform = AffineTransform.identity
            if flags & 0x0008 != 0 { // WE_HAVE_A_SCALE
                guard let scale = Self.f2dot14(data, at: cursor) else { return nil }
                cursor += 2
                transform = AffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: 0)
            } else if flags & 0x0040 != 0 { // X_AND_Y_SCALE
                guard let scaleX = Self.f2dot14(data, at: cursor),
                      let scaleY = Self.f2dot14(data, at: cursor + 2) else { return nil }
                cursor += 4
                transform = AffineTransform(a: scaleX, b: 0, c: 0, d: scaleY, tx: 0, ty: 0)
            } else if flags & 0x0080 != 0 { // TWO_BY_TWO
                guard let a = Self.f2dot14(data, at: cursor),
                      let b = Self.f2dot14(data, at: cursor + 2),
                      let c = Self.f2dot14(data, at: cursor + 4),
                      let d = Self.f2dot14(data, at: cursor + 6) else { return nil }
                cursor += 8
                transform = AffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0)
            }
            transform = transform.concatenating(.translation(x: dx, y: dy))

            if let component = outline(forGlyph: componentIndex, depth: depth + 1) {
                path.addPath(component.applying(transform))
            }

            if flags & 0x0020 == 0 { // no MORE_COMPONENTS
                break
            }
        }
        return path
    }

    // MARK: - Byte Reading

    private static func u8(_ bytes: [UInt8], at offset: Int) -> Int? {
        guard offset >= 0, offset < bytes.count else { return nil }
        return Int(bytes[offset])
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

    private static func tag(_ bytes: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return String(decoding: bytes[offset ..< offset + 4], as: UTF8.self)
    }
}
