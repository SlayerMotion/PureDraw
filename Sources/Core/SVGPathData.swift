//
//  SVGPathData.swift
//  PureDraw
//

import Foundation
import Geometry

/// The single invertible description of the SVG `<path>` `d` attribute and
/// PureDraw's `Path`. Parse and print derive from one description so the two
/// directions cannot drift, per the round-trip law stated in
/// `PureSVG/docs/design/svg-path-roundtrip.md`.
///
/// This is the foundation for SVG import (PureSVG): a `<path d="...">` becomes a
/// `Path`. There is no native Core Graphics SVG path parser, so this stands in
/// for the inbound direction of `CGPath`; the outbound direction is the existing
/// SVG renderer, whose printer this type now owns.
///
/// ## Scope of this slice
///
/// Print is total over every `Path` (all five `PathElement` kinds). Parse covers
/// the normal form: absolute long-form `M L Q C Z`. Surfaces that are valid SVG
/// but not yet implemented (relative commands, `H V S T A`, and implicit repeated
/// coordinate sets) are **rejected** with `nil`, never silently corrupted, and
/// are added in later slices.
public enum SVGPathData {
    // MARK: - Public surface

    /// Parses SVG path data into a `Path`'s element array, or `nil` when the
    /// surface is malformed or uses a command this slice does not yet support.
    public static func parse(_ string: String) -> [PathElement]? {
        var input = Substring(string)
        var elements: [PathElement] = []

        skipSeparators(&input)
        while let first = input.first {
            guard let command = SupportedCommand(rawValue: first) else { return nil }
            input.removeFirst()
            skipSeparators(&input)

            // Z takes no coordinates.
            if command == .close {
                elements.append(.close)
                skipSeparators(&input)
                continue
            }

            // Read exactly `command.pointCount` points; a missing or malformed
            // coordinate rejects the whole surface.
            var points: [Point] = []
            for _ in 0 ..< command.pointCount {
                guard let point = parsePoint(&input) else { return nil }
                points.append(point)
            }
            guard let element = command.element(from: points) else { return nil }
            elements.append(element)
            skipSeparators(&input)
        }

        return elements
    }

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

    // MARK: - Command alphabet (the invertible map between a letter and a PathElement)

    /// The commands this slice parses. Each carries the number of points it
    /// consumes and the forward mapping from those points to a `PathElement`.
    /// The backward mapping (element to letter and points) lives in `print`,
    /// keeping the two directions in one place.
    private enum SupportedCommand {
        case move
        case line
        case quad
        case cubic
        case close

        init?(rawValue: Character) {
            switch rawValue {
            case "M": self = .move
            case "L": self = .line
            case "Q": self = .quad
            case "C": self = .cubic
            // Close is identical absolute or relative, so both letters are accepted.
            case "Z", "z": self = .close
            default: return nil
            }
        }

        var pointCount: Int {
            switch self {
            case .move, .line: 1
            case .quad: 2
            case .cubic: 3
            case .close: 0
            }
        }

        /// Forward: build a `PathElement` from the points just parsed. Point order
        /// matches the normal form printed by `print`.
        func element(from points: [Point]) -> PathElement? {
            switch self {
            case .move where points.count == 1:
                .move(to: points[0])
            case .line where points.count == 1:
                .line(to: points[0])
            case .quad where points.count == 2:
                .quadCurve(to: points[1], control: points[0])
            case .cubic where points.count == 3:
                .cubicCurve(to: points[2], control1: points[0], control2: points[1])
            case .close where points.isEmpty:
                .close
            default:
                nil
            }
        }
    }

    // MARK: - Leaf scanners (honestly invertible numbers and points)

    /// Renders a `Double` as the shortest decimal string that parses back to the
    /// identical value. This is the printer's normal form for numbers and the
    /// inverse of `parseNumber`.
    private static func number(_ value: Double) -> String {
        // `Double.description` is the shortest round-tripping representation.
        value.description
    }

    private static func parsePoint(_ input: inout Substring) -> Point? {
        guard let x = parseNumber(&input) else { return nil }
        skipSeparators(&input)
        guard let y = parseNumber(&input) else { return nil }
        skipSeparators(&input)
        return Point(x: x, y: y)
    }

    /// Consumes a maximal numeric token (optional sign, integer and fraction
    /// digits, optional `e`/`E` exponent) and parses it to a finite `Double`.
    /// Returns `nil` when no number is present or the token is not finite.
    private static func parseNumber(_ input: inout Substring) -> Double? {
        var token = ""

        func takeSign() {
            if let c = input.first, c == "+" || c == "-" {
                token.append(c)
                input.removeFirst()
            }
        }
        func takeDigits() -> Bool {
            var any = false
            while let c = input.first, c.isASCII, c.isNumber {
                token.append(c)
                input.removeFirst()
                any = true
            }
            return any
        }

        takeSign()
        let hadIntDigits = takeDigits()
        var hadFracDigits = false
        if input.first == "." {
            token.append(".")
            input.removeFirst()
            hadFracDigits = takeDigits()
        }
        guard hadIntDigits || hadFracDigits else { return nil }

        if let e = input.first, e == "e" || e == "E" {
            token.append(e)
            input.removeFirst()
            takeSign()
            guard takeDigits() else { return nil }
        }

        guard let value = Double(token), value.isFinite else { return nil }
        return value
    }

    /// Skips SVG separators: ASCII whitespace and commas, in any combination.
    private static func skipSeparators(_ input: inout Substring) {
        while let c = input.first, c == "," || c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0C}" {
            input.removeFirst()
        }
    }
}

public extension Path {
    /// Creates a `Path` by parsing SVG path data (the `<path>` `d` attribute).
    ///
    /// Returns `nil` for malformed input or for commands not yet supported by the
    /// current slice (relative commands, `H V S T A`, and implicit repeated
    /// coordinate sets). Supported: absolute long-form `M L Q C Z`.
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
