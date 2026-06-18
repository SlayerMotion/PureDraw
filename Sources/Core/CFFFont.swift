//
//  CFFFont.swift
//  PureDraw
//

import Geometry

/// Parses a CFF (Compact Font Format) table and interprets its Type 2
/// charstrings into glyph outlines. This is the PostScript-outline counterpart
/// of the `glyf` path, used for OpenType fonts whose sfnt carries a `CFF `
/// table (`OTTO`).
///
/// Coverage is the common Type 2 operator set: moves, lines, the curve
/// families, local and global subroutines with bias, stem hints and hint
/// masks, and endchar. Outlines come back as `Path` values in font units with
/// y pointing up, matching `Font.outline`.
struct CFFFont {
    private let data: [UInt8]
    private let charStrings: [Range<Int>]
    private let globalSubrs: [Range<Int>]
    private let localSubrs: [Range<Int>]
    private let globalBias: Int
    private let localBias: Int

    var numberOfGlyphs: Int {
        charStrings.count
    }

    // MARK: - Parsing

    init?(data bytes: [UInt8], offset: Int, length: Int) {
        guard offset >= 0, offset + length <= bytes.count, length >= 4 else { return nil }
        data = bytes

        // Header: major, minor, hdrSize, offSize.
        let hdrSize = Int(bytes[offset + 2])
        var cursor = offset + hdrSize

        // Name INDEX, Top DICT INDEX, String INDEX, Global Subr INDEX.
        guard let nameIndex = Self.readIndex(bytes, at: cursor) else { return nil }
        cursor = nameIndex.end
        guard let topDictIndex = Self.readIndex(bytes, at: cursor), let topDict = topDictIndex.entries.first else { return nil }
        cursor = topDictIndex.end
        guard let stringIndex = Self.readIndex(bytes, at: cursor) else { return nil }
        cursor = stringIndex.end
        guard let globalSubrIndex = Self.readIndex(bytes, at: cursor) else { return nil }

        globalSubrs = globalSubrIndex.entries
        globalBias = Type2Interpreter.subrBias(globalSubrs.count)

        let top = Self.parseDICT(bytes, range: topDict)

        // CharStrings INDEX (operator 17), offset relative to the CFF table.
        guard let charStringsOffset = top[17]?.last.map({ offset + Int($0) }),
              let charStringsIndex = Self.readIndex(bytes, at: charStringsOffset)
        else { return nil }
        charStrings = charStringsIndex.entries

        // Private DICT (operator 18 = [size, offset]) carries the local Subrs.
        var locals: [Range<Int>] = []
        if let priv = top[18], priv.count == 2 {
            let size = Int(priv[0])
            let privOffset = offset + Int(priv[1])
            if privOffset >= 0, privOffset + size <= bytes.count {
                let privDict = Self.parseDICT(bytes, range: privOffset ..< (privOffset + size))
                if let subrsRel = privDict[19]?.last {
                    let subrsOffset = privOffset + Int(subrsRel)
                    if let subrIndex = Self.readIndex(bytes, at: subrsOffset) {
                        locals = subrIndex.entries
                    }
                }
            }
        }
        localSubrs = locals
        localBias = Type2Interpreter.subrBias(locals.count)
    }

    /// Reads a CFF INDEX: a count, an offset size, `count + 1` offsets, then
    /// the packed objects. Returns each object's byte range and the position
    /// just past the INDEX.
    private static func readIndex(_ bytes: [UInt8], at offset: Int) -> (entries: [Range<Int>], end: Int)? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        let count = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        if count == 0 {
            return (entries: [], end: offset + 2)
        }
        guard offset + 3 <= bytes.count else { return nil }
        let offSize = Int(bytes[offset + 2])
        guard offSize >= 1, offSize <= 4 else { return nil }

        let offsetArrayStart = offset + 3
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
        let end = dataBase + previous
        return (entries: entries, end: end)
    }

    /// Parses a CFF DICT into operator -> operands. Operators are 1 byte, or
    /// 2 bytes when the first is 12 (keyed as `1200 + second`). Operands are integers and reals.
    /// Shared with `CFF2Font`, whose DICTs use the same operand encoding.
    static func parseDICT(_ bytes: [UInt8], range: Range<Int>) -> [Int: [Double]] {
        var result: [Int: [Double]] = [:]
        var operands: [Double] = []
        var cursor = range.lowerBound

        while cursor < range.upperBound {
            let byte = Int(bytes[cursor])
            // Operators are bytes 0...27 (operands begin at 28); 12 introduces a two-byte operator.
            // CFF2 adds operators above 21 (blend 23, vstore 24, maxstack 25) that CFF1 does not use.
            if byte <= 27 {
                let op: Int
                if byte == 12, cursor + 1 < range.upperBound {
                    op = 1200 + Int(bytes[cursor + 1])
                    cursor += 2
                } else {
                    op = byte
                    cursor += 1
                }
                result[op] = operands
                operands.removeAll(keepingCapacity: true)
            } else if byte == 28 {
                guard cursor + 2 < range.upperBound else { break }
                let value = Int(bytes[cursor + 1]) << 8 | Int(bytes[cursor + 2])
                operands.append(Double(Int16(truncatingIfNeeded: value)))
                cursor += 3
            } else if byte == 29 {
                guard cursor + 4 < range.upperBound else { break }
                var value = 0
                for offset in 1 ... 4 {
                    value = value << 8 | Int(bytes[cursor + offset])
                }
                operands.append(Double(Int32(truncatingIfNeeded: value)))
                cursor += 5
            } else if byte == 30 {
                // Real number: BCD nibbles until the 0xf terminator.
                cursor += 1
                var text = ""
                loop: while cursor < range.upperBound {
                    let pair = Int(bytes[cursor])
                    cursor += 1
                    for nibble in [pair >> 4, pair & 0xF] {
                        switch nibble {
                        case 0 ... 9: text.append(Character("\(nibble)"))
                        case 0xA: text.append(".")
                        case 0xB: text.append("E")
                        case 0xC: text.append("E-")
                        case 0xE: text.append("-")
                        case 0xF: break loop
                        default: break
                        }
                    }
                }
                operands.append(Double(text) ?? 0)
            } else if byte >= 32, byte <= 246 {
                operands.append(Double(byte - 139))
                cursor += 1
            } else if byte >= 247, byte <= 250 {
                guard cursor + 1 < range.upperBound else { break }
                operands.append(Double((byte - 247) * 256 + Int(bytes[cursor + 1]) + 108))
                cursor += 2
            } else if byte >= 251, byte <= 254 {
                guard cursor + 1 < range.upperBound else { break }
                operands.append(Double(-(byte - 251) * 256 - Int(bytes[cursor + 1]) - 108))
                cursor += 2
            } else {
                cursor += 1
            }
        }
        return result
    }

    // MARK: - Outline

    func outline(glyphIndex: Int) -> Path? {
        guard glyphIndex >= 0, glyphIndex < charStrings.count else { return nil }
        let interpreter = Type2Interpreter(
            data: data,
            globalSubrs: globalSubrs,
            localSubrs: localSubrs,
            globalBias: globalBias,
            localBias: localBias,
            hasWidth: true
        )
        return interpreter.buildOutline(of: charStrings[glyphIndex])
    }
}
