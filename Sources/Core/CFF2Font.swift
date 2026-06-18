//
//  CFF2Font.swift
//  PureDraw
//

import Geometry

/// A CFF2 (Compact Font Format 2) outline table, the PostScript-outline counterpart of `glyf` used
/// by OpenType variable fonts (PureDraw #78). CFF2 charstrings share the Type 2 operator set with
/// CFF1 (interpreted by `Type2Interpreter`), but the table has a 5-byte header, 32-bit INDEXes, an
/// `FDArray`/`FDSelect` pair that selects per-glyph local subroutines, and an item variation store
/// that drives the `blend` operator. Outlines are produced at the font's default instance: `blend`
/// keeps the default values and drops the region deltas. Non-default instancing would feed the
/// variation store's deltas, which is not done here.
struct CFF2Font {
    private let data: [UInt8]
    private let charStrings: [Range<Int>]
    private let globalSubrs: [Range<Int>]
    private let globalBias: Int
    private let fdLocalSubrs: [[Range<Int>]]
    private let fdLocalBias: [Int]
    private let fdSelect: [Int] // glyph index -> font DICT index
    private let regionCounts: [Int] // region-index count per item variation data (vsindex)

    var glyphCount: Int {
        charStrings.count
    }

    init?(data bytes: [UInt8], offset: Int, length _: Int) {
        guard offset + 5 <= bytes.count, bytes[offset] == 2 else { return nil } // major version 2
        let headerSize = Int(bytes[offset + 2])
        let topDictSize = Int(bytes[offset + 3]) << 8 | Int(bytes[offset + 4])
        let topStart = offset + headerSize
        guard topStart + topDictSize <= bytes.count else { return nil }
        let top = CFFFont.parseDICT(bytes, range: topStart ..< (topStart + topDictSize))

        // The Global Subr INDEX immediately follows the Top DICT.
        guard let globalIndex = Self.readIndex(bytes, at: topStart + topDictSize) else { return nil }
        globalSubrs = globalIndex.entries
        globalBias = Type2Interpreter.subrBias(globalSubrs.count)

        // CharStrings INDEX (operator 17). All DICT offsets are relative to the CFF2 table start.
        guard let charStringsOffset = top[17]?.last.map({ offset + Int($0) }),
              let charStringsIndex = Self.readIndex(bytes, at: charStringsOffset)
        else { return nil }
        charStrings = charStringsIndex.entries

        // FDArray (operator 12 36): one Font DICT per descriptor, each with a Private DICT of subrs.
        guard let fdArrayOffset = top[1236]?.last.map({ offset + Int($0) }),
              let fdArrayIndex = Self.readIndex(bytes, at: fdArrayOffset)
        else { return nil }
        var localsPerFD: [[Range<Int>]] = []
        var biasPerFD: [Int] = []
        for fontDictRange in fdArrayIndex.entries {
            let fontDict = CFFFont.parseDICT(bytes, range: fontDictRange)
            var locals: [Range<Int>] = []
            if let priv = fontDict[18], priv.count == 2 {
                let size = Int(priv[0])
                let privOffset = offset + Int(priv[1])
                if privOffset >= 0, privOffset + size <= bytes.count {
                    let privateDict = CFFFont.parseDICT(bytes, range: privOffset ..< (privOffset + size))
                    if let subrsRelative = privateDict[19]?.last,
                       let subrIndex = Self.readIndex(bytes, at: privOffset + Int(subrsRelative))
                    {
                        locals = subrIndex.entries
                    }
                }
            }
            localsPerFD.append(locals)
            biasPerFD.append(Type2Interpreter.subrBias(locals.count))
        }
        fdLocalSubrs = localsPerFD
        fdLocalBias = biasPerFD

        // FDSelect (operator 12 37) maps each glyph to its Font DICT; absent means all use FD 0.
        var select = [Int](repeating: 0, count: charStrings.count)
        if let fdSelectOffset = top[1237]?.last.map({ offset + Int($0) }),
           let parsed = Self.parseFDSelect(bytes, at: fdSelectOffset, glyphCount: charStrings.count)
        {
            select = parsed
        }
        fdSelect = select

        // VariationStore (operator 24) supplies the region count used to size each blend.
        if let vstoreOffset = top[24]?.last.map({ offset + Int($0) }) {
            regionCounts = Self.variationRegionCounts(bytes, at: vstoreOffset) ?? []
        } else {
            regionCounts = []
        }

        data = bytes
    }

    func outline(glyphIndex: Int) -> Path? {
        guard glyphIndex >= 0, glyphIndex < charStrings.count else { return nil }
        let fd = glyphIndex < fdSelect.count ? fdSelect[glyphIndex] : 0
        let locals = fd >= 0 && fd < fdLocalSubrs.count ? fdLocalSubrs[fd] : []
        let bias = fd >= 0 && fd < fdLocalBias.count ? fdLocalBias[fd] : Type2Interpreter.subrBias(0)
        let counts = regionCounts
        let interpreter = Type2Interpreter(
            data: data,
            globalSubrs: globalSubrs,
            localSubrs: locals,
            globalBias: globalBias,
            localBias: bias,
            hasWidth: false,
            regionCount: { index in index >= 0 && index < counts.count ? counts[index] : 0 }
        )
        return interpreter.buildOutline(of: charStrings[glyphIndex])
    }

    // MARK: - CFF2 structures

    /// A CFF2 INDEX: a 32-bit count, an offset size, `count + 1` offsets, then the data.
    private static func readIndex(_ bytes: [UInt8], at offset: Int) -> (entries: [Range<Int>], end: Int)? {
        guard offset + 4 <= bytes.count else { return nil }
        let count = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        if count == 0 { return (entries: [], end: offset + 4) }
        guard offset + 5 <= bytes.count else { return nil }
        let offSize = Int(bytes[offset + 4])
        guard offSize >= 1, offSize <= 4 else { return nil }

        let offsetArrayStart = offset + 5
        let dataBase = offsetArrayStart + (count + 1) * offSize - 1
        func readOffset(_ index: Int) -> Int? {
            let start = offsetArrayStart + index * offSize
            guard start + offSize <= bytes.count else { return nil }
            var value = 0
            for byte in 0 ..< offSize {
                value = value << 8 | Int(bytes[start + byte])
            }
            return value
        }

        var entries: [Range<Int>] = []
        entries.reserveCapacity(count)
        guard var previous = readOffset(0) else { return nil }
        for index in 1 ... count {
            guard let next = readOffset(index) else { return nil }
            let lower = dataBase + previous
            let upper = dataBase + next
            guard lower >= 0, upper >= lower, upper <= bytes.count else { return nil }
            entries.append(lower ..< upper)
            previous = next
        }
        return (entries: entries, end: dataBase + previous)
    }

    /// Decodes FDSelect format 0 (a per-glyph array) or format 3 (glyph ranges) into glyph -> FD.
    private static func parseFDSelect(_ bytes: [UInt8], at offset: Int, glyphCount: Int) -> [Int]? {
        guard offset < bytes.count, glyphCount > 0 else { return nil }
        var result = [Int](repeating: 0, count: glyphCount)
        switch Int(bytes[offset]) {
        case 0:
            guard offset + 1 + glyphCount <= bytes.count else { return nil }
            for glyph in 0 ..< glyphCount {
                result[glyph] = Int(bytes[offset + 1 + glyph])
            }
            return result
        case 3:
            guard offset + 3 <= bytes.count else { return nil }
            let rangeCount = Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2])
            var cursor = offset + 3
            var ranges: [(first: Int, fd: Int)] = []
            for _ in 0 ..< rangeCount {
                guard cursor + 3 <= bytes.count else { return nil }
                ranges.append((Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1]), Int(bytes[cursor + 2])))
                cursor += 3
            }
            guard cursor + 2 <= bytes.count else { return nil }
            let sentinel = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
            for index in 0 ..< ranges.count {
                let start = ranges[index].first
                let end = index + 1 < ranges.count ? ranges[index + 1].first : sentinel
                for glyph in max(0, start) ..< min(end, glyphCount) {
                    result[glyph] = ranges[index].fd
                }
            }
            return result
        default:
            return nil
        }
    }

    /// The region-index count of each ItemVariationData subtable, indexed by vsindex. `blend` uses it
    /// to know how many region deltas follow the default values on the stack.
    private static func variationRegionCounts(_ bytes: [UInt8], at offset: Int) -> [Int]? {
        // The store is prefixed by a uint16 length; the ItemVariationStore follows.
        let store = offset + 2
        guard store + 8 <= bytes.count else { return nil }
        let dataCount = Int(bytes[store + 6]) << 8 | Int(bytes[store + 7])
        var counts: [Int] = []
        for index in 0 ..< dataCount {
            let entry = store + 8 + index * 4
            guard entry + 4 <= bytes.count else { return nil }
            let dataOffset = Int(bytes[entry]) << 24 | Int(bytes[entry + 1]) << 16 | Int(bytes[entry + 2]) << 8 | Int(bytes[entry + 3])
            let itemVariationData = store + dataOffset
            // ItemVariationData: uint16 itemCount, uint16 wordDeltaCount, uint16 regionIndexCount.
            guard itemVariationData + 6 <= bytes.count else { return nil }
            counts.append(Int(bytes[itemVariationData + 4]) << 8 | Int(bytes[itemVariationData + 5]))
        }
        return counts
    }
}
