//
//  SVGPathData.swift
//  PureDraw
//

import Foundation
import Geometry

/// Converts between the SVG `<path>` `d` attribute and PureDraw's `Path`.
///
/// `print` and the parse of the **normal form** are the invertible core stated in
/// `PureSVG/docs/design/svg-path-roundtrip.md`: print is total over every `Path`
/// and emits the normal form (absolute `M L Q C Z`, single space, shortest
/// round-trip numbers, a leading `M` per subpath), and parsing that normal form
/// recovers the `Path` exactly (the GetPut law).
///
/// `parse` additionally accepts the full SVG path grammar by **lowering** it into
/// that core: relative commands fold to absolute via the current point, `H`/`V`
/// fold to lines, `S`/`T` reconstruct the reflected control point, and elliptic
/// arcs (`A`) lower to cubic Béziers. Lowering is deliberately one-way (a line
/// cannot be recovered as an `H`, an arc cannot be recovered as an `A`), exactly
/// as the design doc states: the round trip is `Path` ↔ normal form, not `Path` ↔
/// arbitrary `d`. Malformed input is rejected with `nil`, never silently corrupted.
public enum SVGPathData {
    // MARK: - Parse (full grammar, lowered into the normal-form core)

    /// Parses SVG path data into a `Path`'s element array, or `nil` when the
    /// surface is malformed.
    public static func parse(_ string: String) -> [PathElement]? {
        var s = Substring(string)
        var elements: [PathElement] = []

        var current = Point.zero // current point
        var subpathStart = Point.zero // start of the current subpath
        var lastCubicControl: Point? // absolute second control of the previous C/S, for S
        var lastQuadControl: Point? // absolute control of the previous Q/T, for T
        var previousCommand: Character = " "
        var hasMoved = false
        var subpathOpen = false // whether a subpath is open (a move since the last close)

        skipSeparators(&s)
        while let lead = s.first {
            // A command letter starts a new command; a number with a prior command
            // is an implicit repeat of that command.
            let command: Character
            if Self.isCommandLetter(lead) {
                command = lead
                s.removeFirst()
                skipSeparators(&s)
            } else if Self.isNumberLead(lead), previousCommand != " " {
                command = previousCommand
                if command == "Z" || command == "z" { return nil } // close takes no coordinates
            } else {
                return nil
            }

            let relative = command.isLowercase
            let base = current

            // A draw command that opens a subpath (the first element, or the first
            // after a close, with no explicit moveto) implicitly begins a new
            // subpath at the current point. Materialize that move so the parsed
            // tree matches what the printer emits, keeping the round trip exact.
            if !"MmZz".contains(command), !subpathOpen {
                elements.append(.move(to: base))
                subpathStart = base
                subpathOpen = true
            }

            switch command {
            case "M", "m":
                // A leading relative moveto is treated as absolute.
                let absolute = !(command == "m" && hasMoved)
                guard let pt = readPoint(&s, base: base, relative: !absolute) else { return nil }
                elements.append(.move(to: pt))
                current = pt
                subpathStart = pt
                hasMoved = true
                subpathOpen = true
                // Subsequent implicit pairs are linetos, relative iff the moveto was.
                previousCommand = (command == "m") ? "l" : "L"
                lastCubicControl = nil
                lastQuadControl = nil

            case "L", "l":
                guard let pt = readPoint(&s, base: base, relative: relative) else { return nil }
                elements.append(.line(to: pt))
                current = pt
                previousCommand = command
                lastCubicControl = nil
                lastQuadControl = nil

            case "H", "h":
                guard let x = readNumber(&s) else { return nil }
                current = Point(x: relative ? base.x + x : x, y: base.y)
                elements.append(.line(to: current))
                previousCommand = command
                lastCubicControl = nil
                lastQuadControl = nil

            case "V", "v":
                guard let y = readNumber(&s) else { return nil }
                current = Point(x: base.x, y: relative ? base.y + y : y)
                elements.append(.line(to: current))
                previousCommand = command
                lastCubicControl = nil
                lastQuadControl = nil

            case "C", "c":
                guard let c1 = readPoint(&s, base: base, relative: relative),
                      let c2 = readPoint(&s, base: base, relative: relative),
                      let end = readPoint(&s, base: base, relative: relative)
                else { return nil }
                elements.append(.cubicCurve(to: end, control1: c1, control2: c2))
                current = end
                previousCommand = command
                lastCubicControl = c2
                lastQuadControl = nil

            case "S", "s":
                guard let c2 = readPoint(&s, base: base, relative: relative),
                      let end = readPoint(&s, base: base, relative: relative)
                else { return nil }
                let c1 = Self.smoothControl(previous: previousCommand, kinds: "CcSs", lastControl: lastCubicControl, current: base)
                elements.append(.cubicCurve(to: end, control1: c1, control2: c2))
                current = end
                previousCommand = command
                lastCubicControl = c2
                lastQuadControl = nil

            case "Q", "q":
                guard let control = readPoint(&s, base: base, relative: relative),
                      let end = readPoint(&s, base: base, relative: relative)
                else { return nil }
                elements.append(.quadCurve(to: end, control: control))
                current = end
                previousCommand = command
                lastQuadControl = control
                lastCubicControl = nil

            case "T", "t":
                guard let end = readPoint(&s, base: base, relative: relative) else { return nil }
                let control = Self.smoothControl(previous: previousCommand, kinds: "QqTt", lastControl: lastQuadControl, current: base)
                elements.append(.quadCurve(to: end, control: control))
                current = end
                previousCommand = command
                lastQuadControl = control
                lastCubicControl = nil

            case "A", "a":
                guard let rx = readNumber(&s), let ry = readNumber(&s), let rot = readNumber(&s),
                      let large = readFlag(&s), let sweep = readFlag(&s),
                      let end = readPoint(&s, base: base, relative: relative)
                else { return nil }
                elements.append(contentsOf: arcToCubics(
                    from: base, rx: rx, ry: ry, xAxisRotationDegrees: rot, largeArc: large, sweep: sweep, to: end
                ))
                current = end
                previousCommand = command
                lastCubicControl = nil
                lastQuadControl = nil

            case "Z", "z":
                elements.append(.close)
                current = subpathStart
                subpathOpen = false
                previousCommand = command
                lastCubicControl = nil
                lastQuadControl = nil

            default:
                return nil
            }

            skipSeparators(&s)
        }

        return elements
    }

    // MARK: - Print (total, normal form, the inverse on the normal-form core)

    /// Renders a path's elements to SVG path data in **normal form**: absolute
    /// `M L Q C Z`, single-space separated, numbers as the shortest decimal that
    /// round-trips the `Double`, and a leading `M` for every subpath.
    ///
    /// Total over every input. An ill-formed path (one whose subpath opens with a
    /// draw command rather than a move) is normalized by emitting an implicit
    /// `M` at the current point, so the output is always valid SVG.
    public static func print(_ elements: [PathElement]) -> String {
        var tokens: [String] = []
        var current = Point.zero
        var subpathStart = Point.zero
        var subpathOpen = false

        func openSubpathIfNeeded() {
            guard !subpathOpen else { return }
            tokens.append("M \(number(current.x)) \(number(current.y))")
            subpathStart = current
            subpathOpen = true
        }

        for element in elements {
            switch element {
            case let .move(to):
                tokens.append("M \(number(to.x)) \(number(to.y))")
                current = to
                subpathStart = to
                subpathOpen = true
            case let .line(to):
                openSubpathIfNeeded()
                tokens.append("L \(number(to.x)) \(number(to.y))")
                current = to
            case let .quadCurve(to, control):
                openSubpathIfNeeded()
                tokens.append("Q \(number(control.x)) \(number(control.y)) \(number(to.x)) \(number(to.y))")
                current = to
            case let .cubicCurve(to, control1, control2):
                openSubpathIfNeeded()
                tokens.append(
                    "C \(number(control1.x)) \(number(control1.y)) "
                        + "\(number(control2.x)) \(number(control2.y)) "
                        + "\(number(to.x)) \(number(to.y))"
                )
                current = to
            case .close:
                openSubpathIfNeeded()
                tokens.append("Z")
                current = subpathStart
                subpathOpen = false
            }
        }

        return tokens.joined(separator: " ")
    }

    // MARK: - Lowering helpers

    private static func isCommandLetter(_ c: Character) -> Bool {
        "MmLlHhVvCcSsQqTtAaZz".contains(c)
    }

    private static func isNumberLead(_ c: Character) -> Bool {
        c.isNumber || c == "." || c == "+" || c == "-"
    }

    /// The reflected control point for a smooth command: reflect the previous
    /// control about the current point when the previous command was of a matching
    /// kind, otherwise coincide with the current point (per SVG 1.1 §8.3.6).
    private static func smoothControl(previous: Character, kinds: String, lastControl: Point?, current: Point) -> Point {
        guard kinds.contains(previous), let last = lastControl else { return current }
        return Point(x: 2 * current.x - last.x, y: 2 * current.y - last.y)
    }

    // MARK: - Elliptic arc to cubic Béziers (SVG 1.1 §F.6)

    private static func arcToCubics(
        from p0: Point, rx rxIn: Double, ry ryIn: Double,
        xAxisRotationDegrees phiDeg: Double, largeArc: Bool, sweep: Bool, to p1: Point
    ) -> [PathElement] {
        // Identical endpoints: the arc is omitted.
        if p0 == p1 { return [] }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        // Zero radius degenerates to a straight line.
        if rx == 0 || ry == 0 { return [.line(to: p1)] }

        let phi = phiDeg * .pi / 180.0
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (p0.x - p1.x) / 2.0
        let dy = (p0.y - p1.y) / 2.0
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Correct out-of-range radii.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = lambda.squareRoot()
            rx *= scale
            ry *= scale
        }

        let rx2 = rx * rx
        let ry2 = ry * ry
        let x1p2 = x1p * x1p
        let y1p2 = y1p * y1p
        let numerator = max(0, rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2)
        let denominator = rx2 * y1p2 + ry2 * x1p2
        var coef = (denominator == 0) ? 0 : (numerator / denominator).squareRoot()
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = -coef * (ry * x1p / rx)

        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2.0
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2.0

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(max(-1, min(1, len == 0 ? 1 : dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var dTheta = angle(ux, uy, vx, vy)
        if !sweep, dTheta > 0 { dTheta -= 2 * .pi }
        if sweep, dTheta < 0 { dTheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / Double(segments)
        let t = 4.0 / 3.0 * tan(delta / 4.0)

        func point(_ theta: Double) -> Point {
            let ct = cos(theta), st = sin(theta)
            return Point(
                x: cosPhi * rx * ct - sinPhi * ry * st + cx,
                y: sinPhi * rx * ct + cosPhi * ry * st + cy
            )
        }
        func derivative(_ theta: Double) -> Point {
            let ct = cos(theta), st = sin(theta)
            return Point(
                x: -cosPhi * rx * st - sinPhi * ry * ct,
                y: -sinPhi * rx * st + cosPhi * ry * ct
            )
        }

        var result: [PathElement] = []
        var theta = theta1
        for _ in 0 ..< segments {
            let theta2 = theta + delta
            let start = point(theta)
            let end = point(theta2)
            let d1 = derivative(theta)
            let d2 = derivative(theta2)
            let c1 = Point(x: start.x + t * d1.x, y: start.y + t * d1.y)
            let c2 = Point(x: end.x - t * d2.x, y: end.y - t * d2.y)
            result.append(.cubicCurve(to: end, control1: c1, control2: c2))
            theta = theta2
        }
        // Snap the final endpoint to the exact target so the current point is exact.
        if case let .cubicCurve(_, c1, c2) = result.last {
            result[result.count - 1] = .cubicCurve(to: p1, control1: c1, control2: c2)
        }
        return result
    }

    // MARK: - Leaf scanners

    private static func number(_ value: Double) -> String {
        value.description
    }

    private static func readPoint(_ s: inout Substring, base: Point, relative: Bool) -> Point? {
        guard let x = readNumber(&s), let y = readNumber(&s) else { return nil }
        return relative ? Point(x: base.x + x, y: base.y + y) : Point(x: x, y: y)
    }

    /// Reads exactly one arc flag (`0` or `1`), which may be packed against the
    /// next token with no separator.
    private static func readFlag(_ s: inout Substring) -> Bool? {
        skipSeparators(&s)
        guard let c = s.first, c == "0" || c == "1" else { return nil }
        s.removeFirst()
        return c == "1"
    }

    /// Skips leading separators, then consumes a maximal numeric token (optional
    /// sign, integer and fraction digits, optional `e`/`E` exponent) and parses it
    /// to a finite `Double`. Returns `nil` when no number is present.
    private static func readNumber(_ s: inout Substring) -> Double? {
        skipSeparators(&s)
        var token = ""

        func takeSign() {
            if let c = s.first, c == "+" || c == "-" {
                token.append(c)
                s.removeFirst()
            }
        }
        func takeDigits() -> Bool {
            var any = false
            while let c = s.first, c.isASCII, c.isNumber {
                token.append(c)
                s.removeFirst()
                any = true
            }
            return any
        }

        takeSign()
        let hadInt = takeDigits()
        var hadFrac = false
        if s.first == "." {
            token.append(".")
            s.removeFirst()
            hadFrac = takeDigits()
        }
        guard hadInt || hadFrac else { return nil }

        if let e = s.first, e == "e" || e == "E" {
            token.append(e)
            s.removeFirst()
            takeSign()
            guard takeDigits() else { return nil }
        }

        // Normalize a leading decimal point (".5", "-.5", "+.5") for Double parsing.
        var normalized = token
        if normalized.hasPrefix(".") {
            normalized = "0" + normalized
        } else if normalized.hasPrefix("-.") {
            normalized = "-0" + normalized.dropFirst()
        } else if normalized.hasPrefix("+.") {
            normalized = "0" + normalized.dropFirst(2)
        }

        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    /// Skips SVG separators: ASCII whitespace and commas, in any combination.
    private static func skipSeparators(_ s: inout Substring) {
        while let c = s.first, c == "," || c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0C}" {
            s.removeFirst()
        }
    }
}

public extension Path {
    /// Creates a `Path` by parsing SVG path data (the `<path>` `d` attribute).
    ///
    /// Accepts the full SVG path grammar (absolute and relative commands, `H`/`V`,
    /// smooth `S`/`T`, elliptic arcs `A`, and implicit repeated coordinates).
    /// Relative commands, `H`/`V`, and `S`/`T` are folded into the normal form and
    /// arcs are lowered to cubic Béziers. Returns `nil` for malformed input.
    ///
    /// There is no Core Graphics SVG path parser to mirror; this is the inbound
    /// stand-in for `CGPath`, paired with ``svgPathData`` as the outbound form.
    init?(svgPathData: String) {
        guard let elements = SVGPathData.parse(svgPathData) else { return nil }
        self.init(elements: elements)
    }

    /// The path rendered as SVG path data in normal form (see ``SVGPathData/print(_:)``).
    /// Total over every path. `Path(svgPathData: path.svgPathData) == path` for
    /// every well-formed path (one whose subpaths open with a move).
    var svgPathData: String {
        SVGPathData.print(elements)
    }
}
