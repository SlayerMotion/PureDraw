//
//  SVGPathDataTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing

struct SVGPathDataTests {
    private func p(_ x: Double, _ y: Double) -> Point {
        Point(x: x, y: y)
    }

    /// Well-formed paths (every subpath opens with a move). These are the values
    /// the round-trip law Λ1 is proved over.
    private var wellFormedPaths: [Path] {
        [
            Path(),
            Path(elements: [.move(to: p(1, 2))]),
            Path(elements: [.move(to: p(1, 2)), .line(to: p(3, 4))]),
            Path(elements: [.move(to: p(1, 2)), .line(to: p(3, 4)), .close]),
            Path(elements: [.move(to: p(0, 0)), .quadCurve(to: p(10, 10), control: p(5, 0))]),
            Path(elements: [.move(to: p(0, 0)), .cubicCurve(to: p(9, 9), control1: p(1, 2), control2: p(3, 4))]),
            Path(elements: [.move(to: p(0, 0)), .line(to: p(1, 1)), .move(to: p(5, 5)), .line(to: p(6, 6)), .close]),
            Path(elements: [.move(to: p(-1.5, 2.25)), .line(to: p(100, -0.5)), .close]),
        ]
    }

    // MARK: - The law

    @Test func lambda1_parseOfPrintRecoversEveryWellFormedPath() {
        for path in wellFormedPaths {
            let printed = path.svgPathData
            let recovered = Path(svgPathData: printed)
            #expect(recovered == path, "Λ1 failed for: \(printed)")
        }
    }

    @Test func lambda2_printOfParseIsIdempotentOnNormalForm() {
        for path in wellFormedPaths {
            let normal = path.svgPathData // by construction in normal form
            let reprinted = Path(svgPathData: normal)?.svgPathData
            #expect(reprinted == normal, "Λ2 failed for: \(normal)")
        }
    }

    // MARK: - Printer normal form

    @Test func printsAbsoluteLongFormNormalForm() {
        #expect(Path().svgPathData == "")
        #expect(Path(elements: [.move(to: p(1, 2))]).svgPathData == "M 1.0 2.0")
        #expect(
            Path(elements: [.move(to: p(1, 2)), .line(to: p(3, 4)), .close]).svgPathData
                == "M 1.0 2.0 L 3.0 4.0 Z"
        )
        #expect(
            Path(elements: [.move(to: p(0, 0)), .quadCurve(to: p(10, 10), control: p(5, 0))]).svgPathData
                == "M 0.0 0.0 Q 5.0 0.0 10.0 10.0"
        )
        #expect(
            Path(elements: [.move(to: p(0, 0)), .cubicCurve(to: p(9, 9), control1: p(1, 2), control2: p(3, 4))]).svgPathData
                == "M 0.0 0.0 C 1.0 2.0 3.0 4.0 9.0 9.0"
        )
    }

    // MARK: - Parser acceptance

    @Test func parsesCompactAndSeparatorVariants() {
        // Commas and missing separators around signs both work.
        #expect(Path(svgPathData: "M 1,2 L 3,4") == Path(elements: [.move(to: p(1, 2)), .line(to: p(3, 4))]))
        #expect(Path(svgPathData: "M1-2") == Path(elements: [.move(to: p(1, -2))]))
        // Exponent numbers.
        #expect(Path(svgPathData: "M 1e2 2.5") == Path(elements: [.move(to: p(100, 2.5))]))
    }

    @Test func emptyAndDegenerateSubpaths() {
        #expect(Path(svgPathData: "") == Path())
        #expect(Path(svgPathData: "   ") == Path())
        #expect(Path(svgPathData: "M 1 2") == Path(elements: [.move(to: p(1, 2))]))
    }

    // MARK: - Full grammar: relative, implicit repeats, H/V

    @Test func parsesRelativeImplicitRepeatsAndHV() {
        // Relative move then relative line: l 2 2 from (1,1) lands at (3,3).
        #expect(Path(svgPathData: "m 1 1 l 2 2") == Path(elements: [.move(to: p(1, 1)), .line(to: p(3, 3))]))
        // Implicit repeated lineto coordinates after an explicit L.
        #expect(
            Path(svgPathData: "M 0 0 L 1 1 2 2")
                == Path(elements: [.move(to: p(0, 0)), .line(to: p(1, 1)), .line(to: p(2, 2))])
        )
        // Implicit lineto pairs after a moveto.
        #expect(
            Path(svgPathData: "M 0 0 1 1 2 2")
                == Path(elements: [.move(to: p(0, 0)), .line(to: p(1, 1)), .line(to: p(2, 2))])
        )
        // Absolute and relative H/V fold to lines.
        #expect(
            Path(svgPathData: "M 0 0 H 5 V 5")
                == Path(elements: [.move(to: p(0, 0)), .line(to: p(5, 0)), .line(to: p(5, 5))])
        )
        #expect(
            Path(svgPathData: "m 0 0 h 5 v 5")
                == Path(elements: [.move(to: p(0, 0)), .line(to: p(5, 0)), .line(to: p(5, 5))])
        )
    }

    // MARK: - Full grammar: smooth S/T control reflection

    @Test func parsesSmoothCubicAndQuadReflection() {
        // After C with second control (2,2) ending at (3,3), S's first control is
        // the reflection of (2,2) about (3,3) = (4,4).
        #expect(
            Path(svgPathData: "M 0 0 C 1 1 2 2 3 3 S 4 4 5 5")
                == Path(elements: [
                    .move(to: p(0, 0)),
                    .cubicCurve(to: p(3, 3), control1: p(1, 1), control2: p(2, 2)),
                    .cubicCurve(to: p(5, 5), control1: p(4, 4), control2: p(4, 4)),
                ])
        )
        // A leading S with no prior cubic uses the current point as the first control.
        #expect(
            Path(svgPathData: "M 1 1 S 2 2 3 3")
                == Path(elements: [.move(to: p(1, 1)), .cubicCurve(to: p(3, 3), control1: p(1, 1), control2: p(2, 2))])
        )
    }

    // MARK: - Full grammar: arcs lower to cubics ending exactly on target

    @Test func parsesArcLoweredToCubicsEndingOnTarget() {
        let path = Path(svgPathData: "M 0 0 A 5 5 0 0 1 10 0")
        let elements = path?.elements ?? []
        #expect(elements.first == .move(to: p(0, 0)))
        #expect(elements.count >= 2) // at least one cubic segment
        // Every lowered element is a cubic, and the last lands exactly on (10, 0).
        let curves = elements.dropFirst()
        #expect(curves.allSatisfy { if case .cubicCurve = $0 { true } else { false } })
        #expect(path?.currentPoint == p(10, 0))
    }

    // MARK: - Rejection (malformed only, never silent corruption)

    @Test func rejectsMalformed() {
        let rejected = [
            "garbage",
            "X 1 2", // unknown command
            "M 1", // missing y coordinate
            "M 1 2 Z @", // trailing garbage after a valid path
            "M 1 2 C 3 4 5 6", // cubic missing its final coordinate pair
            "Z 1 2", // close followed by stray coordinates
        ]
        for surface in rejected {
            #expect(Path(svgPathData: surface) == nil, "expected nil for: \(surface)")
        }
    }

    // MARK: - Adversarial: a reachable Path with no well-formed surface

    @Test func moveLessPathPrintsTotallyAndNormalizes() {
        // A path whose first element is a draw command is reachable via
        // `Path(elements:)`. `print` must be total and emit valid SVG.
        let moveLess = Path(elements: [.line(to: p(3, 4))])
        let printed = moveLess.svgPathData
        #expect(printed == "M 0.0 0.0 L 3.0 4.0")

        // It round-trips to the normalized, geometrically identical well-formed
        // path (an explicit M at the implicit origin), and that form is stable.
        let normalized = Path(svgPathData: printed)
        #expect(normalized == Path(elements: [.move(to: p(0, 0)), .line(to: p(3, 4))]))
        #expect(normalized?.currentPoint == moveLess.currentPoint)
        #expect(normalized?.svgPathData == printed)
    }
}
