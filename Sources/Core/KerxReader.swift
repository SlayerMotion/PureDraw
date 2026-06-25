/// The AAT `kerx` positioning engine: the extended kerning table Core Text uses to
/// position glyphs in Apple fonts, the positioning counterpart to `morx`. Derived
/// from the Apple TrueType Reference Manual ("The 'kerx' table"); Core Text is the
/// differential oracle, never a source.
///
/// `kerx` is a list of subtables, each contributing a horizontal adjustment to the
/// glyph run. This reader implements the formats Apple complex fonts use: format 2,
/// class-based pair kerning, and format 4, anchor-point attachment (the AAT
/// mark-to-base positioning that seats a Myanmar subscript under its base), which
/// reads the `ankr` table for the anchors. The contextual state-machine kerning
/// (format 1) and vertical and cross-stream subtables are not applied; the cases
/// that need them are disclosed by the caller.
///
/// Self-contained like ``MorxReader``: it holds the raw bytes and the table offset
/// and reads with its own accessors, so `Font` keeps its buffer private.
struct KerxReader {
    private let data: [UInt8]
    /// Byte offset of the `kerx` table within `data`.
    private let base: Int
    /// Byte offset of the `ankr` anchor-points table, or nil when absent. Format-4
    /// anchor attachment resolves its anchors from it.
    private let ankrBase: Int?
    /// The number of glyphs in the font, the bound for format-0 lookup arrays.
    private let glyphCount: Int

    init(data: [UInt8], base: Int, ankrBase: Int?, glyphCount: Int) {
        self.data = data
        self.base = base
        self.ankrBase = ankrBase
        self.glyphCount = glyphCount
    }

    private func u16(_ offset: Int) -> Int? {
        guard offset >= 0, offset + 1 < data.count else { return nil }
        return Int(data[offset]) << 8 | Int(data[offset + 1])
    }

    private func i16(_ offset: Int) -> Int? {
        guard let value = u16(offset) else { return nil }
        return value >= 0x8000 ? value - 0x10000 : value
    }

    private func u32(_ offset: Int) -> Int? {
        guard offset >= 0, offset + 3 < data.count else { return nil }
        return Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
    }

    /// The horizontal kerning adjustments for `glyphs`, one per glyph: element `i` is
    /// the advance adjustment applied before glyph `i` (the kerning between glyph
    /// `i - 1` and glyph `i`), in font units. Element 0 is always 0. The caller
    /// shifts each glyph and the ones after it by the cumulative sum.
    ///
    /// Only same-stream subtables (format 2 class pair kerning) contribute; vertical
    /// and cross-stream subtables are skipped, so the result is the horizontal
    /// in-line kerning, which is what `morx`-shaped runs need on top of the glyph
    /// advances.
    func horizontalAdjustments(_ glyphs: [Int]) -> [Int] {
        var adjustments = [Int](repeating: 0, count: glyphs.count)
        guard let nTables = u32(base + 4) else { return adjustments }
        var subtableStart = base + 8
        for _ in 0 ..< nTables {
            guard let length = u32(subtableStart), let coverage = u32(subtableStart + 4) else { break }
            let format = coverage & 0xFF
            // Coverage high bits: vertical (0x80000000) and cross-stream
            // (0x40000000) subtables do not contribute to horizontal advance.
            let vertical = (coverage & 0x8000_0000) != 0
            let crossStream = (coverage & 0x4000_0000) != 0
            if !vertical, !crossStream {
                switch format {
                case 0: accumulateFormat0(subtableStart: subtableStart, glyphs: glyphs, into: &adjustments)
                case 1: accumulateFormat1(subtableStart: subtableStart, glyphs: glyphs, into: &adjustments)
                case 2: accumulateFormat2(subtableStart: subtableStart, glyphs: glyphs, into: &adjustments)
                default: break
                }
            }
            subtableStart += length
        }
        return adjustments
    }

    /// Format 0: an ordered list of (left glyph, right glyph) pairs, each with a
    /// kerning value, sorted so the pair for two adjacent glyphs is found by binary
    /// search. The classic `kern` format 0, widened to 32-bit counts.
    private func accumulateFormat0(subtableStart: Int, glyphs: [Int], into adjustments: inout [Int]) {
        let body = subtableStart + 12
        guard let nPairs = u32(body) else { return }
        let pairs = body + 16
        for index in 1 ..< glyphs.count {
            let key = glyphs[index - 1] << 16 | glyphs[index]
            var low = 0
            var high = nPairs
            while low < high {
                let mid = (low + high) / 2
                let pair = pairs + mid * 6
                guard let left = u16(pair), let right = u16(pair + 2) else { break }
                let probe = left << 16 | right
                if probe == key {
                    if let value = i16(pair + 4) { adjustments[index] += value }
                    break
                }
                if key < probe { high = mid } else { low = mid + 1 }
            }
        }
    }

    /// Format 1: state-machine kerning. As the machine walks, a `push` entry stacks
    /// the current glyph; an entry carrying a value offset pops the stacked glyphs and
    /// applies successive kerning values to them, the value list terminated by a value
    /// with its low bit set. (Apple TrueType Reference Manual, "Format 1".)
    private func accumulateFormat1(subtableStart: Int, glyphs: [Int], into adjustments: inout [Int]) {
        let body = subtableStart + 12
        guard let nClasses = u32(body),
              let classOffset = u32(body + 4),
              let stateOffset = u32(body + 8),
              let entryOffset = u32(body + 12)
        else {
            return
        }
        let classTable = body + classOffset
        let stateArray = body + stateOffset
        let entryTable = body + entryOffset

        var state = 0
        var index = 0
        var stack: [Int] = []
        var safety = 0
        let limit = (glyphs.count + 1) * 4 + 64
        while index <= glyphs.count, safety < limit {
            safety += 1
            let classValue = index < glyphs.count ? classOf(glyphs[index], classTable: classTable, nClasses: nClasses) : SM.endOfText
            guard let entryIdx = u16(stateArray + (state * nClasses + classValue) * 2),
                  let newState = u16(entryTable + entryIdx * 4),
                  let flags = u16(entryTable + entryIdx * 4 + 2)
            else {
                break
            }
            if (flags & 0x8000) != 0, index < glyphs.count {
                stack.append(index)
            }
            let valueOffset = flags & 0x3FFF
            if valueOffset != 0 {
                var valuePtr = subtableStart + valueOffset
                while !stack.isEmpty, let raw = i16(valuePtr) {
                    valuePtr += 2
                    let glyphIndex = stack.removeLast()
                    // The low bit is the list terminator, not part of the value.
                    let value = raw & ~1
                    if value != 0, glyphIndex >= 1, glyphIndex < adjustments.count {
                        adjustments[glyphIndex] += value
                    }
                    if raw & 1 != 0 { break }
                }
            }
            state = newState
            if (flags & SM.dontAdvance) == 0 { index += 1 }
        }
    }

    /// Format 2: class-based pair kerning. The left glyph selects a row, the right
    /// glyph a column, into a value array; the i16 there is the kerning between them.
    /// The class-table and array offsets are measured from the start of the subtable
    /// (the length field), not from the format-2 body.
    private func accumulateFormat2(subtableStart: Int, glyphs: [Int], into adjustments: inout [Int]) {
        let body = subtableStart + 12
        guard let leftOffset = u32(body + 4),
              let rightOffset = u32(body + 8),
              let arrayOffset = u32(body + 12)
        else {
            return
        }
        let leftTable = subtableStart + leftOffset
        let rightTable = subtableStart + rightOffset
        let array = subtableStart + arrayOffset
        for index in 1 ..< glyphs.count {
            // The class lookups already yield byte offsets: the left value is a row
            // offset (a multiple of the row width), the right value a column offset
            // (a multiple of 2). The kerning is the i16 at array + left + right.
            let left = aatLookup(glyphs[index - 1], at: leftTable) ?? 0
            let right = aatLookup(glyphs[index], at: rightTable) ?? 0
            if let value = i16(array + left + right), value != 0 {
                adjustments[index] += value
            }
        }
    }

    /// The AAT `kerx` format-4 anchor attachments for `glyphs`: each says a glyph
    /// should attach to an earlier glyph by aligning an anchor on each, the anchors
    /// resolved from the `ankr` table. Empty when the font carries no `ankr` table or
    /// no format-4 subtable. This is the AAT mark-to-base attachment, the mechanism
    /// that seats a Myanmar subscript under its base.
    func anchorAttachments(_ glyphs: [Int]) -> [KerxAnchorAttachment] {
        guard let ankrBase, let nTables = u32(base + 4) else { return [] }
        var result: [KerxAnchorAttachment] = []
        var subtableStart = base + 8
        for _ in 0 ..< nTables {
            guard let length = u32(subtableStart), let coverage = u32(subtableStart + 4) else { break }
            if (coverage & 0xFF) == 4 {
                walkFormat4(subtableStart: subtableStart, glyphs: glyphs, ankrBase: ankrBase, into: &result)
            }
            subtableStart += length
        }
        return result
    }

    /// The fixed AAT class numbers and the entry flag bits the format-4 state machine
    /// uses.
    private enum SM {
        static let endOfText = 0
        static let outOfBounds = 1
        static let setMark = 0x8000
        static let dontAdvance = 0x4000
        static let noAction = 0xFFFF
    }

    /// Walks the format-4 state machine of one subtable, emitting an attachment each
    /// time an entry names an action while a glyph is marked. The action indexes a
    /// pair of anchor indices (marked glyph's anchor, current glyph's anchor) in the
    /// subtable's points table; the anchors come from `ankr`.
    private func walkFormat4(subtableStart: Int, glyphs: [Int], ankrBase: Int, into result: inout [KerxAnchorAttachment]) {
        let body = subtableStart + 12
        guard let nClasses = u32(body),
              let classOffset = u32(body + 4),
              let stateOffset = u32(body + 8),
              let entryOffset = u32(body + 12),
              let flags = u32(body + 16)
        else {
            return
        }
        let classTable = body + classOffset
        let stateArray = body + stateOffset
        let entryTable = body + entryOffset
        let pointsTable = body + (flags & 0x00FF_FFFF)

        var state = 0
        var index = 0
        var markedIndex = -1
        var safety = 0
        let limit = (glyphs.count + 1) * 4 + 64
        while index <= glyphs.count, safety < limit {
            safety += 1
            let classValue = index < glyphs.count ? classOf(glyphs[index], classTable: classTable, nClasses: nClasses) : SM.endOfText
            guard let entryIdx = u16(stateArray + (state * nClasses + classValue) * 2) else { break }
            let entry = entryTable + entryIdx * 6
            guard let newState = u16(entry), let entryFlags = u16(entry + 2), let actionIndex = u16(entry + 4) else { break }

            if actionIndex != SM.noAction, markedIndex >= 0, index < glyphs.count {
                if let markedAnchorIndex = u16(pointsTable + actionIndex * 4),
                   let currentAnchorIndex = u16(pointsTable + actionIndex * 4 + 2),
                   let marked = ankrAnchor(glyph: glyphs[markedIndex], index: markedAnchorIndex, ankrBase: ankrBase),
                   let current = ankrAnchor(glyph: glyphs[index], index: currentAnchorIndex, ankrBase: ankrBase)
                {
                    result.append(KerxAnchorAttachment(
                        currentIndex: index,
                        markedIndex: markedIndex,
                        markedAnchorX: marked.x,
                        markedAnchorY: marked.y,
                        currentAnchorX: current.x,
                        currentAnchorY: current.y
                    ))
                }
            }
            if (entryFlags & SM.setMark) != 0 { markedIndex = index }
            state = newState
            if (entryFlags & SM.dontAdvance) == 0 { index += 1 }
        }
    }

    /// The class of `glyph` for the format-4 state machine.
    private func classOf(_ glyph: Int, classTable: Int, nClasses: Int) -> Int {
        guard let value = aatLookup(glyph, at: classTable), value < nClasses else { return SM.outOfBounds }
        return value
    }

    /// The `index`-th anchor point of `glyph` from the `ankr` table, in font units.
    /// The `ankr` header is a u16 version, a u16 flags, then the u32 offsets to the
    /// glyph-to-data lookup and the data table of point lists. (Apple TrueType
    /// Reference Manual, "The 'ankr' table".)
    private func ankrAnchor(glyph: Int, index: Int, ankrBase: Int) -> (x: Int, y: Int)? {
        guard let lookupOffset = u32(ankrBase + 4), let dataOffset = u32(ankrBase + 8) else { return nil }
        guard let glyphDataOffset = aatLookup(glyph, at: ankrBase + lookupOffset) else { return nil }
        let pointsBase = ankrBase + dataOffset + glyphDataOffset
        guard let count = u32(pointsBase), index >= 0, index < count else { return nil }
        guard let x = i16(pointsBase + 4 + index * 4), let y = i16(pointsBase + 4 + index * 4 + 2) else { return nil }
        return (x, y)
    }

    /// Reads an AAT lookup table at `offset`, returning the value for `glyph`, or nil.
    /// Supports the formats `kerx` class tables use: 0 (array), 2 (segment single),
    /// 4 (segment array), 6 (single table), 8 (trimmed array).
    private func aatLookup(_ glyph: Int, at offset: Int) -> Int? {
        guard let format = u16(offset) else { return nil }
        switch format {
        case 0:
            guard glyph >= 0, glyph < glyphCount else { return nil }
            return u16(offset + 2 + glyph * 2)
        case 2:
            return segmentSingle(glyph, at: offset)
        case 4:
            return segmentArray(glyph, at: offset)
        case 6:
            return singleTable(glyph, at: offset)
        case 8:
            guard let first = u16(offset + 2), let count = u16(offset + 4) else { return nil }
            guard glyph >= first, glyph < first + count else { return nil }
            return u16(offset + 6 + (glyph - first) * 2)
        default:
            return nil
        }
    }

    private func segmentSingle(_ glyph: Int, at offset: Int) -> Int? {
        guard let unitSize = u16(offset + 2), let nUnits = u16(offset + 4) else { return nil }
        let segments = offset + 12
        for index in 0 ..< nUnits {
            let unit = segments + index * unitSize
            guard let last = u16(unit), let first = u16(unit + 2), let value = u16(unit + 4) else { break }
            if last == 0xFFFF, first == 0xFFFF { break }
            if glyph >= first, glyph <= last { return value }
        }
        return nil
    }

    private func segmentArray(_ glyph: Int, at offset: Int) -> Int? {
        guard let unitSize = u16(offset + 2), let nUnits = u16(offset + 4) else { return nil }
        let segments = offset + 12
        for index in 0 ..< nUnits {
            let unit = segments + index * unitSize
            guard let last = u16(unit), let first = u16(unit + 2), let valueOffset = u16(unit + 4) else { break }
            if last == 0xFFFF, first == 0xFFFF { break }
            if glyph >= first, glyph <= last {
                return u16(offset + valueOffset + (glyph - first) * 2)
            }
        }
        return nil
    }

    private func singleTable(_ glyph: Int, at offset: Int) -> Int? {
        guard let unitSize = u16(offset + 2), let nUnits = u16(offset + 4) else { return nil }
        let units = offset + 12
        var low = 0
        var high = nUnits
        while low < high {
            let mid = (low + high) / 2
            let unit = units + mid * unitSize
            guard let key = u16(unit) else { return nil }
            if glyph == key { return u16(unit + 2) }
            if glyph < key { high = mid } else { low = mid + 1 }
        }
        return nil
    }
}
