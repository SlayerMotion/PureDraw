//
//  Type2Interpreter.swift
//  PureDraw
//

import Geometry

/// A Type 2 charstring interpreter shared by CFF (CFF1) and CFF2 outlines. The geometric operators
/// (moves, lines, the four curve families, subroutine calls with bias) are identical between the two
/// formats. The differences are injected by the caller: CFF1 charstrings carry a leading glyph width
/// on the first stack-clearing operator (`hasWidth`), while CFF2 charstrings instead use the `blend`
/// and `vsindex` variation operators and end implicitly. At the default variation instance, `blend`
/// keeps the default values and drops the region deltas, so `regionCount` need only report how many
/// deltas each `vsindex` selects.
struct Type2Interpreter {
    let data: [UInt8]
    let globalSubrs: [Range<Int>]
    let localSubrs: [Range<Int>]
    let globalBias: Int
    let localBias: Int
    let hasWidth: Bool
    let regionCount: (Int) -> Int

    init(
        data: [UInt8],
        globalSubrs: [Range<Int>],
        localSubrs: [Range<Int>],
        globalBias: Int,
        localBias: Int,
        hasWidth: Bool,
        regionCount: @escaping (Int) -> Int = { _ in 0 }
    ) {
        self.data = data
        self.globalSubrs = globalSubrs
        self.localSubrs = localSubrs
        self.globalBias = globalBias
        self.localBias = localBias
        self.hasWidth = hasWidth
        self.regionCount = regionCount
    }

    /// The standard subroutine-index bias (CFF spec): 107, 1131, or 32768 by population.
    static func subrBias(_ count: Int) -> Int {
        if count < 1240 { return 107 }
        if count < 33900 { return 1131 }
        return 32768
    }

    func buildOutline(of range: Range<Int>) -> Path? {
        var state = State()
        run(range, into: &state, depth: 0)
        state.closeOpenContour()
        return state.path.elements.isEmpty ? nil : state.path
    }

    /// Mutable interpreter state shared across subroutine calls.
    private struct State {
        var path = Path()
        var x = 0.0
        var y = 0.0
        var stack: [Double] = []
        var stemCount = 0
        var widthParsed = false
        var hasOpenContour = false
        var finished = false
        var vsindex = 0

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

        /// Drops a leading width operand on the first stack-clearing operator (CFF1 only).
        mutating func takeWidth(evenArgs: Bool) {
            guard !widthParsed else { return }
            widthParsed = true
            if stack.count % 2 == (evenArgs ? 1 : 0), !stack.isEmpty {
                stack.removeFirst()
            }
        }
    }

    private func run(_ range: Range<Int>, into state: inout State, depth: Int) {
        guard depth < 10 else { return }
        var cursor = range.lowerBound

        while cursor < range.upperBound, !state.finished {
            let byte = Int(data[cursor])
            cursor += 1

            if byte >= 32 || byte == 28 {
                if byte == 28 {
                    guard cursor + 1 < data.count else { break }
                    let value = Int(data[cursor]) << 8 | Int(data[cursor + 1])
                    state.stack.append(Double(Int16(truncatingIfNeeded: value)))
                    cursor += 2
                } else if byte <= 246 {
                    state.stack.append(Double(byte - 139))
                } else if byte <= 250 {
                    guard cursor < data.count else { break }
                    state.stack.append(Double((byte - 247) * 256 + Int(data[cursor]) + 108))
                    cursor += 1
                } else if byte <= 254 {
                    guard cursor < data.count else { break }
                    state.stack.append(Double(-(byte - 251) * 256 - Int(data[cursor]) - 108))
                    cursor += 1
                } else {
                    guard cursor + 3 < data.count else { break }
                    var value = 0
                    for offset in 0 ..< 4 {
                        value = value << 8 | Int(data[cursor + offset])
                    }
                    state.stack.append(Double(Int32(truncatingIfNeeded: value)) / 65536.0)
                    cursor += 4
                }
                continue
            }

            execute(operator: byte, cursor: &cursor, range: range, state: &state, depth: depth)
        }
    }

    private func execute(operator op: Int, cursor: inout Int, range: Range<Int>, state: inout State, depth: Int) {
        switch op {
        case 1, 3, 18, 23: // hstem, vstem, hstemhm, vstemhm
            if hasWidth { state.takeWidth(evenArgs: true) }
            state.stemCount += state.stack.count / 2
            state.stack.removeAll(keepingCapacity: true)

        case 19, 20: // hintmask, cntrmask
            if hasWidth { state.takeWidth(evenArgs: true) }
            state.stemCount += state.stack.count / 2
            state.stack.removeAll(keepingCapacity: true)
            cursor += (state.stemCount + 7) / 8

        case 21: // rmoveto
            if hasWidth { state.takeWidth(evenArgs: true) }
            if state.stack.count >= 2 {
                state.x += state.stack[0]
                state.y += state.stack[1]
            }
            state.moveTo()
            state.stack.removeAll(keepingCapacity: true)

        case 22: // hmoveto
            if hasWidth, !state.widthParsed, state.stack.count > 1 { state.stack.removeFirst() }
            state.widthParsed = true
            if let dx = state.stack.first { state.x += dx }
            state.moveTo()
            state.stack.removeAll(keepingCapacity: true)

        case 4: // vmoveto
            if hasWidth, !state.widthParsed, state.stack.count > 1 { state.stack.removeFirst() }
            state.widthParsed = true
            if let dy = state.stack.first { state.y += dy }
            state.moveTo()
            state.stack.removeAll(keepingCapacity: true)

        case 5: // rlineto
            var index = 0
            while index + 2 <= state.stack.count {
                state.x += state.stack[index]
                state.y += state.stack[index + 1]
                state.lineTo()
                index += 2
            }
            state.stack.removeAll(keepingCapacity: true)

        case 6, 7: // hlineto, vlineto: alternating axis
            var horizontal = (op == 6)
            for value in state.stack {
                if horizontal { state.x += value } else { state.y += value }
                state.lineTo()
                horizontal.toggle()
            }
            state.stack.removeAll(keepingCapacity: true)

        case 8: // rrcurveto
            var index = 0
            while index + 6 <= state.stack.count {
                appendCurve(
                    &state,
                    dx1: state.stack[index], dy1: state.stack[index + 1],
                    dx2: state.stack[index + 2], dy2: state.stack[index + 3],
                    dx3: state.stack[index + 4], dy3: state.stack[index + 5]
                )
                index += 6
            }
            state.stack.removeAll(keepingCapacity: true)

        case 24: // rcurveline
            var index = 0
            while index + 6 <= state.stack.count - 2 {
                appendCurve(
                    &state,
                    dx1: state.stack[index], dy1: state.stack[index + 1],
                    dx2: state.stack[index + 2], dy2: state.stack[index + 3],
                    dx3: state.stack[index + 4], dy3: state.stack[index + 5]
                )
                index += 6
            }
            if index + 1 < state.stack.count {
                state.x += state.stack[index]
                state.y += state.stack[index + 1]
                state.lineTo()
            }
            state.stack.removeAll(keepingCapacity: true)

        case 25: // rlinecurve
            var index = 0
            while index + 2 <= state.stack.count - 6 {
                state.x += state.stack[index]
                state.y += state.stack[index + 1]
                state.lineTo()
                index += 2
            }
            if index + 6 <= state.stack.count {
                appendCurve(
                    &state,
                    dx1: state.stack[index], dy1: state.stack[index + 1],
                    dx2: state.stack[index + 2], dy2: state.stack[index + 3],
                    dx3: state.stack[index + 4], dy3: state.stack[index + 5]
                )
            }
            state.stack.removeAll(keepingCapacity: true)

        case 26: // vvcurveto
            var index = 0
            var dx1 = 0.0
            if state.stack.count % 4 == 1 {
                dx1 = state.stack[0]
                index = 1
            }
            while index + 4 <= state.stack.count {
                appendCurve(
                    &state,
                    dx1: dx1, dy1: state.stack[index],
                    dx2: state.stack[index + 1], dy2: state.stack[index + 2],
                    dx3: 0, dy3: state.stack[index + 3]
                )
                dx1 = 0
                index += 4
            }
            state.stack.removeAll(keepingCapacity: true)

        case 27: // hhcurveto
            var index = 0
            var dy1 = 0.0
            if state.stack.count % 4 == 1 {
                dy1 = state.stack[0]
                index = 1
            }
            while index + 4 <= state.stack.count {
                appendCurve(
                    &state,
                    dx1: state.stack[index], dy1: dy1,
                    dx2: state.stack[index + 1], dy2: state.stack[index + 2],
                    dx3: state.stack[index + 3], dy3: 0
                )
                dy1 = 0
                index += 4
            }
            state.stack.removeAll(keepingCapacity: true)

        case 30, 31: // vhcurveto, hvcurveto: alternating tangents
            interpretAlternatingCurves(startHorizontal: op == 31, state: &state)
            state.stack.removeAll(keepingCapacity: true)

        case 15: // vsindex (CFF2): selects the variation-region set for subsequent blends
            if let value = state.stack.popLast() { state.vsindex = Int(value) }
            state.stack.removeAll(keepingCapacity: true)

        case 16: // blend (CFF2): at the default instance keep the n defaults, drop the region deltas
            guard let count = state.stack.popLast().map(Int.init), count >= 0 else {
                state.stack.removeAll(keepingCapacity: true)
                return
            }
            let deltaCount = count * regionCount(state.vsindex)
            if state.stack.count >= deltaCount { state.stack.removeLast(deltaCount) }
            // The n default values stay on the stack for the operator that follows.

        case 10: // callsubr
            if let index = state.stack.popLast().map({ Int($0) + localBias }), index >= 0, index < localSubrs.count {
                run(localSubrs[index], into: &state, depth: depth + 1)
            }

        case 29: // callgsubr
            if let index = state.stack.popLast().map({ Int($0) + globalBias }), index >= 0, index < globalSubrs.count {
                run(globalSubrs[index], into: &state, depth: depth + 1)
            }

        case 11: // return
            cursor = range.upperBound

        case 14: // endchar (CFF1)
            if hasWidth { state.takeWidth(evenArgs: true) }
            state.closeOpenContour()
            state.finished = true

        default:
            state.stack.removeAll(keepingCapacity: true)
        }
    }

    private func appendCurve(_ state: inout State, dx1: Double, dy1: Double, dx2: Double, dy2: Double, dx3: Double, dy3: Double) {
        let c1 = Point(x: state.x + dx1, y: state.y + dy1)
        let c2 = Point(x: c1.x + dx2, y: c1.y + dy2)
        let end = Point(x: c2.x + dx3, y: c2.y + dy3)
        state.curveTo(c1, c2, end)
        state.x = end.x
        state.y = end.y
    }

    /// vhcurveto / hvcurveto: curves whose start and end tangents alternate between horizontal and
    /// vertical, with an optional final fifth operand.
    private func interpretAlternatingCurves(startHorizontal: Bool, state: inout State) {
        var index = 0
        var horizontal = startHorizontal
        let count = state.stack.count

        while count - index >= 4 {
            let remaining = count - index
            let last = (remaining == 5) ? state.stack[index + 4] : 0.0
            if horizontal {
                appendCurve(
                    &state,
                    dx1: state.stack[index], dy1: 0,
                    dx2: state.stack[index + 1], dy2: state.stack[index + 2],
                    dx3: last, dy3: state.stack[index + 3]
                )
            } else {
                appendCurve(
                    &state,
                    dx1: 0, dy1: state.stack[index],
                    dx2: state.stack[index + 1], dy2: state.stack[index + 2],
                    dx3: state.stack[index + 3], dy3: last
                )
            }
            index += 4
            horizontal.toggle()
        }
    }
}
