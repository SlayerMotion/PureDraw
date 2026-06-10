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
        globalBias = Self.subrBias(globalSubrs.count)

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
        localBias = Self.subrBias(locals.count)
    }

    private static func subrBias(_ count: Int) -> Int {
        if count < 1240 { return 107 }
        if count < 33900 { return 1131 }
        return 32768
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
    /// 2 bytes when the first is 12. Operands are integers and reals.
    private static func parseDICT(_ bytes: [UInt8], range: Range<Int>) -> [Int: [Double]] {
        var result: [Int: [Double]] = [:]
        var operands: [Double] = []
        var cursor = range.lowerBound

        while cursor < range.upperBound {
            let byte = Int(bytes[cursor])
            if byte <= 21 {
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
        var builder = OutlineBuilder()
        run(charStrings[glyphIndex], into: &builder, depth: 0)
        builder.closeOpenContour()
        return builder.path.elements.isEmpty ? nil : builder.path
    }

    /// Mutable interpreter state shared across subroutine calls.
    private struct OutlineBuilder {
        var path = Path()
        var x = 0.0
        var y = 0.0
        var stack: [Double] = []
        var stemCount = 0
        var widthParsed = false
        var hasOpenContour = false
        var finished = false

        mutating func moveTo() {
            closeOpenContour()
            path.move(to: Point(x: x, y: y))
            hasOpenContour = true
        }

        mutating func lineTo() {
            path.addLine(to: Point(x: x, y: y))
        }

        mutating func curveTo(_ c1: Point, _ c2: Point, _ end: Point) {
            path.addCurve(to: end, control1: c1, control2: c2)
        }

        mutating func closeOpenContour() {
            if hasOpenContour {
                path.closeSubpath()
                hasOpenContour = false
            }
        }

        /// Drops a leading width operand on the first stack-clearing operator.
        mutating func takeWidth(evenArgs: Bool) {
            guard !widthParsed else { return }
            widthParsed = true
            if stack.count % 2 == (evenArgs ? 1 : 0), !stack.isEmpty {
                stack.removeFirst()
            }
        }
    }

    private func run(_ range: Range<Int>, into builder: inout OutlineBuilder, depth: Int) {
        guard depth < 10 else { return }
        var cursor = range.lowerBound

        while cursor < range.upperBound, !builder.finished {
            let byte = Int(data[cursor])
            cursor += 1

            if byte >= 32 || byte == 28 {
                // Operand.
                if byte == 28 {
                    guard cursor + 1 < data.count else { break }
                    let value = Int(data[cursor]) << 8 | Int(data[cursor + 1])
                    builder.stack.append(Double(Int16(truncatingIfNeeded: value)))
                    cursor += 2
                } else if byte <= 246 {
                    builder.stack.append(Double(byte - 139))
                } else if byte <= 250 {
                    guard cursor < data.count else { break }
                    builder.stack.append(Double((byte - 247) * 256 + Int(data[cursor]) + 108))
                    cursor += 1
                } else if byte <= 254 {
                    guard cursor < data.count else { break }
                    builder.stack.append(Double(-(byte - 251) * 256 - Int(data[cursor]) - 108))
                    cursor += 1
                } else {
                    // 255: 16.16 fixed.
                    guard cursor + 3 < data.count else { break }
                    var value = 0
                    for offset in 0 ..< 4 {
                        value = value << 8 | Int(data[cursor + offset])
                    }
                    builder.stack.append(Double(Int32(truncatingIfNeeded: value)) / 65536.0)
                    cursor += 4
                }
                continue
            }

            execute(operator: byte, cursor: &cursor, range: range, builder: &builder, depth: depth)
        }
    }

    private func execute(operator op: Int, cursor: inout Int, range: Range<Int>, builder: inout OutlineBuilder, depth: Int) {
        switch op {
        case 1, 3, 18, 23: // hstem, vstem, hstemhm, vstemhm
            builder.takeWidth(evenArgs: true)
            builder.stemCount += builder.stack.count / 2
            builder.stack.removeAll(keepingCapacity: true)

        case 19, 20: // hintmask, cntrmask
            builder.takeWidth(evenArgs: true)
            builder.stemCount += builder.stack.count / 2
            builder.stack.removeAll(keepingCapacity: true)
            cursor += (builder.stemCount + 7) / 8

        case 21: // rmoveto
            builder.takeWidth(evenArgs: true)
            if builder.stack.count >= 2 {
                builder.x += builder.stack[0]
                builder.y += builder.stack[1]
            }
            builder.moveTo()
            builder.stack.removeAll(keepingCapacity: true)

        case 22: // hmoveto
            if !builder.widthParsed, builder.stack.count > 1 { builder.stack.removeFirst() }
            builder.widthParsed = true
            if let dx = builder.stack.first { builder.x += dx }
            builder.moveTo()
            builder.stack.removeAll(keepingCapacity: true)

        case 4: // vmoveto
            if !builder.widthParsed, builder.stack.count > 1 { builder.stack.removeFirst() }
            builder.widthParsed = true
            if let dy = builder.stack.first { builder.y += dy }
            builder.moveTo()
            builder.stack.removeAll(keepingCapacity: true)

        case 5: // rlineto
            var index = 0
            while index + 2 <= builder.stack.count {
                builder.x += builder.stack[index]
                builder.y += builder.stack[index + 1]
                builder.lineTo()
                index += 2
            }
            builder.stack.removeAll(keepingCapacity: true)

        case 6, 7: // hlineto, vlineto: alternating axis
            var horizontal = (op == 6)
            for value in builder.stack {
                if horizontal { builder.x += value } else { builder.y += value }
                builder.lineTo()
                horizontal.toggle()
            }
            builder.stack.removeAll(keepingCapacity: true)

        case 8: // rrcurveto
            var index = 0
            while index + 6 <= builder.stack.count {
                appendCurve(
                    &builder,
                    dx1: builder.stack[index],
                    dy1: builder.stack[index + 1],
                    dx2: builder.stack[index + 2],
                    dy2: builder.stack[index + 3],
                    dx3: builder.stack[index + 4],
                    dy3: builder.stack[index + 5]
                )
                index += 6
            }
            builder.stack.removeAll(keepingCapacity: true)

        case 24: // rcurveline
            var index = 0
            while index + 6 <= builder.stack.count - 2 {
                appendCurve(
                    &builder,
                    dx1: builder.stack[index],
                    dy1: builder.stack[index + 1],
                    dx2: builder.stack[index + 2],
                    dy2: builder.stack[index + 3],
                    dx3: builder.stack[index + 4],
                    dy3: builder.stack[index + 5]
                )
                index += 6
            }
            if index + 1 < builder.stack.count {
                builder.x += builder.stack[index]
                builder.y += builder.stack[index + 1]
                builder.lineTo()
            }
            builder.stack.removeAll(keepingCapacity: true)

        case 25: // rlinecurve
            var index = 0
            while index + 2 <= builder.stack.count - 6 {
                builder.x += builder.stack[index]
                builder.y += builder.stack[index + 1]
                builder.lineTo()
                index += 2
            }
            if index + 6 <= builder.stack.count {
                appendCurve(
                    &builder,
                    dx1: builder.stack[index],
                    dy1: builder.stack[index + 1],
                    dx2: builder.stack[index + 2],
                    dy2: builder.stack[index + 3],
                    dx3: builder.stack[index + 4],
                    dy3: builder.stack[index + 5]
                )
            }
            builder.stack.removeAll(keepingCapacity: true)

        case 26: // vvcurveto
            var index = 0
            var dx1 = 0.0
            if builder.stack.count % 4 == 1 {
                dx1 = builder.stack[0]
                index = 1
            }
            while index + 4 <= builder.stack.count {
                appendCurve(
                    &builder,
                    dx1: dx1,
                    dy1: builder.stack[index],
                    dx2: builder.stack[index + 1],
                    dy2: builder.stack[index + 2],
                    dx3: 0,
                    dy3: builder.stack[index + 3]
                )
                dx1 = 0
                index += 4
            }
            builder.stack.removeAll(keepingCapacity: true)

        case 27: // hhcurveto
            var index = 0
            var dy1 = 0.0
            if builder.stack.count % 4 == 1 {
                dy1 = builder.stack[0]
                index = 1
            }
            while index + 4 <= builder.stack.count {
                appendCurve(
                    &builder,
                    dx1: builder.stack[index],
                    dy1: dy1,
                    dx2: builder.stack[index + 1],
                    dy2: builder.stack[index + 2],
                    dx3: builder.stack[index + 3],
                    dy3: 0
                )
                dy1 = 0
                index += 4
            }
            builder.stack.removeAll(keepingCapacity: true)

        case 30, 31: // vhcurveto, hvcurveto: alternating tangents
            interpretAlternatingCurves(startHorizontal: op == 31, builder: &builder)
            builder.stack.removeAll(keepingCapacity: true)

        case 10: // callsubr
            if let index = builder.stack.popLast().map({ Int($0) + localBias }), index >= 0, index < localSubrs.count {
                run(localSubrs[index], into: &builder, depth: depth + 1)
            }

        case 29: // callgsubr
            if let index = builder.stack.popLast().map({ Int($0) + globalBias }), index >= 0, index < globalSubrs.count {
                run(globalSubrs[index], into: &builder, depth: depth + 1)
            }

        case 11: // return
            cursor = range.upperBound

        case 14: // endchar
            builder.takeWidth(evenArgs: true)
            builder.closeOpenContour()
            builder.finished = true

        default:
            builder.stack.removeAll(keepingCapacity: true)
        }
    }

    private func appendCurve(_ builder: inout OutlineBuilder, dx1: Double, dy1: Double, dx2: Double, dy2: Double, dx3: Double, dy3: Double) {
        let c1 = Point(x: builder.x + dx1, y: builder.y + dy1)
        let c2 = Point(x: c1.x + dx2, y: c1.y + dy2)
        let end = Point(x: c2.x + dx3, y: c2.y + dy3)
        builder.curveTo(c1, c2, end)
        builder.x = end.x
        builder.y = end.y
    }

    /// vhcurveto / hvcurveto: curves whose start and end tangents alternate
    /// between horizontal and vertical, with an optional final fifth operand.
    private func interpretAlternatingCurves(startHorizontal: Bool, builder: inout OutlineBuilder) {
        var index = 0
        var horizontal = startHorizontal
        let count = builder.stack.count

        while count - index >= 4 {
            let remaining = count - index
            let last = (remaining == 5) ? builder.stack[index + 4] : 0.0
            if horizontal {
                appendCurve(
                    &builder,
                    dx1: builder.stack[index],
                    dy1: 0,
                    dx2: builder.stack[index + 1],
                    dy2: builder.stack[index + 2],
                    dx3: last,
                    dy3: builder.stack[index + 3]
                )
            } else {
                appendCurve(
                    &builder,
                    dx1: 0,
                    dy1: builder.stack[index],
                    dx2: builder.stack[index + 1],
                    dy2: builder.stack[index + 2],
                    dx3: builder.stack[index + 3],
                    dy3: last
                )
            }
            index += 4
            horizontal.toggle()
        }
    }
}
