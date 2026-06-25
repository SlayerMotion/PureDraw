/// The AAT `morx` shaping engine: it drives a font's extended glyph metamorphosis
/// chain over a glyph sequence, the way Core Text does for Apple fonts that carry
/// `morx` (most complex-script system fonts). Derived from the Apple TrueType
/// Reference Manual ("The 'morx' table" and "Font tables: state tables"), a public
/// specification; Core Text is the differential oracle, never a source.
///
/// `morx` is a chain of subtables, each a transformation applied in turn to the
/// glyph run. Four of the five subtable kinds are finite state machines over an
/// extended state table (a glyph-class lookup, a state array, and an entry table);
/// the fifth is a plain glyph-to-glyph lookup. The engine processes the enabled
/// subtables in order, threading the glyph buffer through each.
///
/// Self-contained by design: it holds the raw bytes and the table offset and reads
/// everything it needs with its own accessors, so `Font` keeps its byte buffer
/// private and simply hands the offset to this reader.
struct MorxReader {
    private let data: [UInt8]
    /// Byte offset of the `morx` table within `data`.
    private let base: Int
    /// The number of glyphs in the font, the bound for format-0 lookup arrays.
    private let glyphCount: Int

    init(data: [UInt8], base: Int, glyphCount: Int) {
        self.data = data
        self.base = base
        self.glyphCount = glyphCount
    }

    // MARK: Byte accessors

    private func u16(_ offset: Int) -> Int? {
        guard offset >= 0, offset + 1 < data.count else { return nil }
        return Int(data[offset]) << 8 | Int(data[offset + 1])
    }

    private func u32(_ offset: Int) -> Int? {
        guard offset >= 0, offset + 3 < data.count else { return nil }
        return Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
    }

    // MARK: Chain processing

    /// Applies the whole `morx` chain to `input`, returning the transformed glyphs.
    /// Each glyph carries the input index it derives from, so the caller keeps
    /// clusters across reordering, ligature, and insertion. A malformed table
    /// returns the input unchanged.
    func apply(_ input: [MorxGlyph]) -> [MorxGlyph] {
        guard let nChains = u32(base + 4) else { return input }
        var glyphs = input
        var chainStart = base + 8
        for _ in 0 ..< nChains {
            guard let defaultFlags = u32(chainStart),
                  let chainLength = u32(chainStart + 4),
                  let nFeatures = u32(chainStart + 8),
                  let nSubtables = u32(chainStart + 12)
            else {
                break
            }
            // The default feature selection is baked into defaultFlags; with no
            // caller-requested features the enabled set is exactly those bits.
            let flags = defaultFlags
            var subtableStart = chainStart + 16 + nFeatures * 12
            for _ in 0 ..< nSubtables {
                guard let length = u32(subtableStart),
                      let coverage = u32(subtableStart + 4),
                      let subFeatureFlags = u32(subtableStart + 8)
                else {
                    break
                }
                let type = coverage & 0xFF
                // Process only subtables the active flags enable. The descending
                // (0x40000000) and vertical (0x80000000) orientations are not taken:
                // this engine shapes horizontal, logical-order runs.
                let enabled = (flags & subFeatureFlags) != 0
                let vertical = (coverage & 0x8000_0000) != 0
                if enabled, !vertical {
                    let body = subtableStart + 12
                    glyphs = applySubtable(type: type, body: body, length: length - 12, glyphs: glyphs)
                }
                subtableStart += length
            }
            chainStart += chainLength
        }
        return glyphs
    }

    private func applySubtable(type: Int, body: Int, length _: Int, glyphs: [MorxGlyph]) -> [MorxGlyph] {
        switch type {
        case 0: applyRearrangement(body: body, glyphs: glyphs)
        case 1: applyContextual(body: body, glyphs: glyphs)
        case 2: applyLigature(body: body, glyphs: glyphs)
        case 4: applyNonContextual(body: body, glyphs: glyphs)
        case 5: applyInsertion(body: body, glyphs: glyphs)
        default: glyphs
        }
    }

    // MARK: AAT lookup table (glyph -> value)

    /// Reads an AAT lookup table at `offset` (relative to the font), returning the
    /// value mapped to `glyph`, or nil when the glyph is absent. Supports the lookup
    /// formats `morx` uses: 0 (trimmed-array-by-index is format 6 here; 0 is a plain
    /// array), 2 (segment single), 4 (segment array), 6 (single table), 8 (trimmed
    /// array). The class and substitution tables of state machines are these lookups.
    private func aatLookup(_ glyph: Int, at offset: Int, glyphCount: Int) -> Int? {
        guard let format = u16(offset) else { return nil }
        switch format {
        case 0:
            // Simple array: one u16 value per glyph, indexed by glyph id.
            guard glyph >= 0, glyph < glyphCount else { return nil }
            return u16(offset + 2 + glyph * 2)
        case 2:
            return aatSegmentSingle(glyph, at: offset)
        case 4:
            return aatSegmentArray(glyph, at: offset)
        case 6:
            return aatSingleTable(glyph, at: offset)
        case 8:
            // Trimmed array: firstGlyph, glyphCount, then values.
            guard let first = u16(offset + 2), let count = u16(offset + 4) else { return nil }
            guard glyph >= first, glyph < first + count else { return nil }
            return u16(offset + 6 + (glyph - first) * 2)
        default:
            return nil
        }
    }

    /// Format 2: ordered segments, each a single value for the whole range.
    private func aatSegmentSingle(_ glyph: Int, at offset: Int) -> Int? {
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

    /// Format 4: ordered segments, each pointing at a per-glyph value array.
    private func aatSegmentArray(_ glyph: Int, at offset: Int) -> Int? {
        guard let unitSize = u16(offset + 2), let nUnits = u16(offset + 4) else { return nil }
        let segments = offset + 12
        for index in 0 ..< nUnits {
            let unit = segments + index * unitSize
            guard let last = u16(unit), let first = u16(unit + 2), let valueOffset = u16(unit + 4) else { break }
            if last == 0xFFFF, first == 0xFFFF { break }
            if glyph >= first, glyph <= last {
                // valueOffset is from the table start to a u16 array indexed by
                // (glyph - first).
                return u16(offset + valueOffset + (glyph - first) * 2)
            }
        }
        return nil
    }

    /// Format 6: single glyph lookups, a sorted (glyph, value) array.
    private func aatSingleTable(_ glyph: Int, at offset: Int) -> Int? {
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

    // MARK: Extended state machine

    /// The fixed AAT class numbers and the dont-advance flag bit, shared by every
    /// state-machine subtable.
    private enum SM {
        static let endOfText = 0
        static let outOfBounds = 1
        static let deletedGlyph = 2
        static let dontAdvance = 0x4000
    }

    /// The class of `glyph` for a state machine whose class lookup is at
    /// `classTable`, applying the fixed classes for the out-of-bounds and deleted
    /// cases. `nClasses` bounds the result.
    private func classOf(_ glyph: Int, classTable: Int, nClasses: Int, glyphCount: Int) -> Int {
        if glyph == 0xFFFF { return SM.deletedGlyph }
        guard let value = aatLookup(glyph, at: classTable, glyphCount: glyphCount), value < nClasses else {
            return SM.outOfBounds
        }
        return value
    }

    /// Reads the four shared state-table header offsets (relative to `body`).
    private func stateHeader(body: Int) -> (nClasses: Int, classTable: Int, stateArray: Int, entryTable: Int)? {
        guard let nClasses = u32(body),
              let classOffset = u32(body + 4),
              let stateOffset = u32(body + 8),
              let entryOffset = u32(body + 12)
        else {
            return nil
        }
        return (nClasses, body + classOffset, body + stateOffset, body + entryOffset)
    }

    /// The entry index in the state array for `state` and `class`.
    private func entryIndex(stateArray: Int, state: Int, classValue: Int, nClasses: Int) -> Int? {
        u16(stateArray + (state * nClasses + classValue) * 2)
    }

    // MARK: Subtable type 4: non-contextual substitution

    /// A plain glyph-to-glyph lookup applied to every glyph.
    private func applyNonContextual(body: Int, glyphs: [MorxGlyph]) -> [MorxGlyph] {
        glyphs.map { glyph in
            guard let substitute = aatLookup(glyph.glyphID, at: body, glyphCount: glyphCount), substitute != 0 else {
                return glyph
            }
            return MorxGlyph(glyphID: substitute, cluster: glyph.cluster)
        }
    }

    // MARK: Subtable type 2: ligature

    /// Ligature state machine: it pushes component glyphs onto a stack as it walks,
    /// and on a perform-action entry walks the ligature action list to fold the
    /// marked components into a single ligature glyph. (Apple TrueType Reference
    /// Manual, "Ligature subtable".)
    private func applyLigature(body: Int, glyphs: [MorxGlyph]) -> [MorxGlyph] {
        guard let header = stateHeader(body: body),
              let ligActionOffset = u32(body + 16),
              let componentOffset = u32(body + 20),
              let ligatureOffset = u32(body + 24)
        else {
            return glyphs
        }
        let ligActionTable = body + ligActionOffset
        let componentTable = body + componentOffset
        let ligatureTable = body + ligatureOffset

        // Consumed components are marked deleted (a sentinel glyph id) in place so the
        // walk's indices stay stable, then compacted out at the end.
        let deleted = -1
        var result = glyphs
        var state = 0
        var index = 0
        var componentStack: [Int] = []
        var safety = 0
        let limit = (result.count + 1) * 8 + 64

        while index <= result.count, safety < limit {
            safety += 1
            let glyphHere = index < result.count ? result[index].glyphID : 0xFFFF
            let classValue = index < result.count
                ? classOf(glyphHere, classTable: header.classTable, nClasses: header.nClasses, glyphCount: glyphCount)
                : SM.endOfText
            guard let entryIdx = entryIndex(stateArray: header.stateArray, state: state, classValue: classValue, nClasses: header.nClasses) else { break }
            let entry = header.entryTable + entryIdx * 6
            guard let newState = u16(entry), let flags = u16(entry + 2), let ligActionIndex = u16(entry + 4) else { break }
            let setComponent = (flags & 0x8000) != 0
            let performAction = (flags & 0x2000) != 0

            if setComponent {
                componentStack.append(index)
            }
            if performAction {
                foldLigature(
                    result: &result,
                    componentStack: &componentStack,
                    deleted: deleted,
                    ligActionStart: ligActionTable + ligActionIndex * 4,
                    componentTable: componentTable,
                    ligatureTable: ligatureTable
                )
            }
            state = newState
            if (flags & SM.dontAdvance) == 0 { index += 1 }
        }
        return result.filter { $0.glyphID != deleted }
    }

    /// Walks the ligature action list from `ligActionStart`, accumulating a ligature
    /// index from the marked components on the stack. The ligature glyph replaces the
    /// last component popped (the first glyph of the ligature), and the earlier
    /// components are marked deleted. (Apple TrueType Reference Manual, "Ligature
    /// subtable": the action loop and the component and ligature lists.)
    private func foldLigature(
        result: inout [MorxGlyph],
        componentStack: inout [Int],
        deleted: Int,
        ligActionStart: Int,
        componentTable: Int,
        ligatureTable: Int
    ) {
        var actionPtr = ligActionStart
        var ligatureIndex = 0
        var consumed: [Int] = []
        var safety = 0
        while safety < 64, componentStack.isEmpty == false {
            safety += 1
            guard let action = u32(actionPtr) else { break }
            actionPtr += 4
            let last = (action & 0x8000_0000) != 0
            let store = (action & 0x4000_0000) != 0
            // The action's low 30 bits are a signed offset added to the component
            // glyph id to index the component table.
            var offset = action & 0x3FFF_FFFF
            if offset & 0x2000_0000 != 0 { offset -= 0x4000_0000 }

            let componentIndex = componentStack.removeLast()
            consumed.append(componentIndex)
            let componentGlyph = result[componentIndex].glyphID
            if let value = u16(componentTable + (componentGlyph + offset) * 2) {
                ligatureIndex += value
            }
            if last || store {
                if let ligatureGlyph = u16(ligatureTable + ligatureIndex * 2) {
                    // The last component popped is the ligature's first glyph; it
                    // becomes the ligature and inherits the earliest cluster. The
                    // earlier-popped components are deleted.
                    let target = componentIndex
                    let cluster = consumed.map { result[$0].cluster }.min() ?? result[target].cluster
                    for earlier in consumed where earlier != target {
                        result[earlier] = MorxGlyph(glyphID: deleted, cluster: result[earlier].cluster)
                    }
                    result[target] = MorxGlyph(glyphID: ligatureGlyph, cluster: cluster)
                    // The new ligature can itself be a component of a further one.
                    componentStack.append(target)
                }
                ligatureIndex = 0
                consumed.removeAll()
            }
            if last { break }
        }
    }

    // MARK: Subtable type 1: contextual substitution

    /// Contextual glyph substitution: the state machine marks a glyph and, per
    /// entry, substitutes the marked glyph and/or the current glyph through per-entry
    /// lookup tables. (Apple TrueType Reference Manual, "Contextual glyph
    /// substitution subtable".)
    private func applyContextual(body: Int, glyphs: [MorxGlyph]) -> [MorxGlyph] {
        guard let header = stateHeader(body: body), let substTableOffset = u32(body + 16) else { return glyphs }
        let substTable = body + substTableOffset

        var result = glyphs
        var state = 0
        var index = 0
        var markIndex = -1
        var safety = 0
        let limit = (result.count + 1) * 4 + 64
        while index <= result.count, safety < limit {
            safety += 1
            let classValue = index < result.count
                ? classOf(result[index].glyphID, classTable: header.classTable, nClasses: header.nClasses, glyphCount: glyphCount)
                : SM.endOfText
            guard let entryIdx = entryIndex(stateArray: header.stateArray, state: state, classValue: classValue, nClasses: header.nClasses) else { break }
            let entry = header.entryTable + entryIdx * 8
            guard let newState = u16(entry), let flags = u16(entry + 2), let markSubst = u16(entry + 4), let currentSubst = u16(entry + 6) else { break }

            if markSubst != 0xFFFF, markIndex >= 0, markIndex < result.count {
                if let sub = substituteIndex(table: substTable, listIndex: markSubst, glyph: result[markIndex].glyphID) {
                    result[markIndex] = MorxGlyph(glyphID: sub, cluster: result[markIndex].cluster)
                }
            }
            if currentSubst != 0xFFFF, index < result.count {
                if let sub = substituteIndex(table: substTable, listIndex: currentSubst, glyph: result[index].glyphID) {
                    result[index] = MorxGlyph(glyphID: sub, cluster: result[index].cluster)
                }
            }
            if (flags & 0x8000) != 0 { markIndex = index }
            state = newState
            if (flags & SM.dontAdvance) == 0 { index += 1 }
        }
        return result
    }

    /// The contextual substitution tables are a list of per-class AAT lookups; the
    /// entry's index selects which lookup, then the glyph maps through it.
    private func substituteIndex(table: Int, listIndex: Int, glyph: Int) -> Int? {
        // The substitution table is an offset list (u32 each) to AAT lookups.
        guard let lookupOffset = u32(table + listIndex * 4) else {
            // Some fonts store the substitution tables as a flat single lookup; fall
            // back to treating the table itself as one lookup.
            return aatLookup(glyph, at: table, glyphCount: glyphCount)
        }
        let value = aatLookup(glyph, at: table + lookupOffset, glyphCount: glyphCount)
        return (value == 0) ? nil : value
    }

    // MARK: Subtable type 0: rearrangement

    /// Glyph rearrangement: the state machine marks a first and last glyph and, per
    /// entry verb, reorders the glyphs of that marked range. The 16 verbs are the
    /// canonical AAT rearrangement set. (Apple TrueType Reference Manual, "Rearrangement subtable".)
    private func applyRearrangement(body: Int, glyphs: [MorxGlyph]) -> [MorxGlyph] {
        guard let header = stateHeader(body: body) else { return glyphs }
        var result = glyphs
        var state = 0
        var index = 0
        var firstMark = -1
        var lastMark = -1
        var safety = 0
        let limit = (result.count + 1) * 4 + 64
        while index <= result.count, safety < limit {
            safety += 1
            let classValue = index < result.count
                ? classOf(result[index].glyphID, classTable: header.classTable, nClasses: header.nClasses, glyphCount: glyphCount)
                : SM.endOfText
            guard let entryIdx = entryIndex(stateArray: header.stateArray, state: state, classValue: classValue, nClasses: header.nClasses) else { break }
            let entry = header.entryTable + entryIdx * 4
            guard let newState = u16(entry), let flags = u16(entry + 2) else { break }
            let markFirst = (flags & 0x8000) != 0
            let markLast = (flags & 0x2000) != 0
            let verb = flags & 0x000F

            if markFirst { firstMark = index }
            if markLast { lastMark = index }
            if verb != 0, firstMark >= 0, lastMark >= firstMark, lastMark < result.count {
                result = rearrange(result, first: firstMark, last: lastMark, verb: verb)
            }
            state = newState
            if (flags & SM.dontAdvance) == 0 { index += 1 }
        }
        return result
    }

    /// Applies one of the 16 AAT rearrangement verbs to the marked range
    /// `[first, last]`, where A and B are the first one or two glyphs, C and D the
    /// last one or two, and x the middle.
    private func rearrange(_ glyphs: [MorxGlyph], first: Int, last: Int, verb: Int) -> [MorxGlyph] {
        var range = Array(glyphs[first ... last])
        let count = range.count
        func reorder(_ block: [MorxGlyph]) {
            range = block
        }
        switch verb {
        case 1 where count >= 1: // Ax => xA
            reorder(Array(range[1...]) + [range[0]])
        case 2 where count >= 1: // xD => Dx
            reorder([range[count - 1]] + Array(range[0 ..< count - 1]))
        case 3 where count >= 2: // AxD => DxA
            reorder([range[count - 1]] + Array(range[1 ..< count - 1]) + [range[0]])
        case 4 where count >= 2: // ABx => xAB
            reorder(Array(range[2...]) + [range[0], range[1]])
        case 5 where count >= 2: // ABx => xBA
            reorder(Array(range[2...]) + [range[1], range[0]])
        case 6 where count >= 2: // xCD => CDx
            reorder([range[count - 2], range[count - 1]] + Array(range[0 ..< count - 2]))
        case 7 where count >= 2: // xCD => DCx
            reorder([range[count - 1], range[count - 2]] + Array(range[0 ..< count - 2]))
        case 8 where count >= 3: // AxCD => CDxA
            reorder([range[count - 2], range[count - 1]] + Array(range[1 ..< count - 2]) + [range[0]])
        case 9 where count >= 3: // AxCD => DCxA
            reorder([range[count - 1], range[count - 2]] + Array(range[1 ..< count - 2]) + [range[0]])
        case 10 where count >= 3: // ABxD => DxAB
            reorder([range[count - 1]] + Array(range[2 ..< count - 1]) + [range[0], range[1]])
        case 11 where count >= 3: // ABxD => DxBA
            reorder([range[count - 1]] + Array(range[2 ..< count - 1]) + [range[1], range[0]])
        case 12 where count >= 4: // ABxCD => CDxAB
            reorder([range[count - 2], range[count - 1]] + Array(range[2 ..< count - 2]) + [range[0], range[1]])
        case 13 where count >= 4: // ABxCD => CDxBA
            reorder([range[count - 2], range[count - 1]] + Array(range[2 ..< count - 2]) + [range[1], range[0]])
        case 14 where count >= 4: // ABxCD => DCxAB
            reorder([range[count - 1], range[count - 2]] + Array(range[2 ..< count - 2]) + [range[0], range[1]])
        case 15 where count >= 4: // ABxCD => DCxBA
            reorder([range[count - 1], range[count - 2]] + Array(range[2 ..< count - 2]) + [range[1], range[0]])
        default:
            return glyphs
        }
        var out = glyphs
        out.replaceSubrange(first ... last, with: range)
        return out
    }

    // MARK: Subtable type 5: glyph insertion

    /// Glyph insertion: the state machine inserts glyphs from an insertion list
    /// before or after the current or marked glyph. (Apple TrueType Reference
    /// Manual, "Glyph insertion subtable".)
    private func applyInsertion(body: Int, glyphs: [MorxGlyph]) -> [MorxGlyph] {
        guard let header = stateHeader(body: body), let insertionOffset = u32(body + 16) else { return glyphs }
        let insertionTable = body + insertionOffset

        var result = glyphs
        var state = 0
        var index = 0
        var markIndex = -1
        var safety = 0
        let limit = (result.count + 1) * 8 + 128
        while index <= result.count, safety < limit {
            safety += 1
            let classValue = index < result.count
                ? classOf(result[index].glyphID, classTable: header.classTable, nClasses: header.nClasses, glyphCount: glyphCount)
                : SM.endOfText
            guard let entryIdx = entryIndex(stateArray: header.stateArray, state: state, classValue: classValue, nClasses: header.nClasses) else { break }
            let entry = header.entryTable + entryIdx * 8
            guard let newState = u16(entry), let flags = u16(entry + 2), let currentInsert = u16(entry + 4), let markedInsert = u16(entry + 6) else { break }

            let currentIsKashidaLike = (flags & 0x2000) != 0
            let currentInsertBefore = (flags & 0x0800) != 0
            let currentCount = (flags & 0x03E0) >> 5
            let markedInsertBefore = (flags & 0x0400) != 0
            let markedCount = (flags & 0x001F)
            _ = currentIsKashidaLike

            // Marked insertion first (it is positioned earlier in the buffer), then
            // current, so the index bookkeeping below stays consistent.
            var inserted = 0
            if markedInsert != 0xFFFF, markedCount > 0, markIndex >= 0, markIndex <= result.count {
                let newGlyphs = insertionGlyphs(table: insertionTable, start: markedInsert, count: markedCount, near: markIndex < result.count ? result[markIndex].cluster : 0)
                let at = markedInsertBefore ? markIndex : markIndex + 1
                result.insert(contentsOf: newGlyphs, at: min(at, result.count))
                inserted += newGlyphs.count
                if at <= index { index += newGlyphs.count }
            }
            if currentInsert != 0xFFFF, currentCount > 0, index <= result.count {
                let curIndex = index
                let newGlyphs = insertionGlyphs(
                    table: insertionTable,
                    start: currentInsert,
                    count: currentCount,
                    near: curIndex < result.count ? result[curIndex].cluster : (result.last?.cluster ?? 0)
                )
                let at = currentInsertBefore ? curIndex : curIndex + 1
                result.insert(contentsOf: newGlyphs, at: min(at, result.count))
                inserted += newGlyphs.count
            }
            if (flags & 0x8000) != 0 { markIndex = index }
            state = newState
            if (flags & SM.dontAdvance) == 0 { index += 1 + inserted }
        }
        return result
    }

    private func insertionGlyphs(table: Int, start: Int, count: Int, near cluster: Int) -> [MorxGlyph] {
        var out: [MorxGlyph] = []
        for offset in 0 ..< count {
            guard let glyph = u16(table + (start + offset) * 2) else { break }
            out.append(MorxGlyph(glyphID: glyph, cluster: cluster))
        }
        return out
    }
}
