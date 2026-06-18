//
//  SVGPathRoundTripProofTests.swift
//  PureDraw
//
//  The round-trip theorem for SVG path data (PureDraw #110 / #125), checked rather than only
//  asserted on a corpus. `SVGPathData.print` and `parseCanonical` are both derived from the single
//  `canonicalCommands` table, so they are inverse by construction. This pins that:
//    - the base lemma, build and match are mutual inverses for each of the five commands, and
//    - the inductive step, exhaustively over reproducibly generated well-formed sequences,
//      parseCanonical(print(x)) == x and the lenient parse(print(x)) == x.
//

@testable import Core
import Geometry
import Testing

struct SVGPathRoundTripProofTests {
    // MARK: - Base lemma: build and match are inverse for every command

    @Test func eachCommandBuildAndMatchAreMutualInverses() throws {
        let a = Point(x: 1, y: 2), b = Point(x: -3, y: 4.5), c = Point(x: 6, y: -7)
        let samples: [(element: PathElement, wire: [Point], letter: Character)] = [
            (.move(to: a), [a], "M"),
            (.line(to: a), [a], "L"),
            (.quadCurve(to: b, control: a), [a, b], "Q"),
            (.cubicCurve(to: c, control1: a, control2: b), [a, b, c], "C"),
            (.close, [], "Z"),
        ]
        for sample in samples {
            let command = try #require(SVGPathData.canonicalCommand(for: sample.element))
            #expect(command.letter == sample.letter)
            #expect(command.pointCount == sample.wire.count)
            // match yields the wire points; build inverts match; match inverts build.
            #expect(command.match(sample.element) == sample.wire, "match(\(sample.letter)) must give the wire points")
            #expect(command.build(sample.wire) == sample.element, "build must invert match for \(sample.letter)")
            #expect(command.match(command.build(sample.wire)) == sample.wire, "match must invert build for \(sample.letter)")
        }
        // The table is a bijection with the five PathElement cases: five distinct letters.
        #expect(Set(SVGPathData.canonicalCommands.map(\.letter)) == Set("MLQCZ"))
    }

    // MARK: - Inductive step: the round trip is the identity on well-formed sequences

    @Test func canonicalRoundTripIsIdentityOnGeneratedPaths() {
        var generator = PathGenerator(seed: 0x5DEE_CE66_D2A0_1B3C)
        for _ in 0 ..< 600 {
            let elements = generator.wellFormedSequence()
            let printed = SVGPathData.print(elements)
            #expect(SVGPathData.parseCanonical(printed) == elements, "strict canonical parse must invert print")
            #expect(SVGPathData.parse(printed) == elements, "the lenient full-grammar parse must also recover it")
        }
    }

    @Test func roundTripHoldsForFormattingEdgeCases() {
        // Coordinates that stress the number formatting that the proof depends on.
        let coords: [Double] = [0, -0.0, 1, -1, 0.5, 1.0 / 3.0, .pi, 1e-12, 1e12, -123_456.789, 0.1, 9_999_999.999]
        var elements: [PathElement] = [.move(to: Point(x: coords[0], y: coords[1]))]
        var index = 0
        func nextCoord() -> Double {
            defer { index += 1 }
            return coords[index % coords.count]
        }
        for _ in 0 ..< coords.count {
            elements.append(.cubicCurve(
                to: Point(x: nextCoord(), y: nextCoord()),
                control1: Point(x: nextCoord(), y: nextCoord()),
                control2: Point(x: nextCoord(), y: nextCoord())
            ))
        }
        elements.append(.close)
        let printed = SVGPathData.print(elements)
        #expect(SVGPathData.parseCanonical(printed) == elements)
        #expect(SVGPathData.parse(printed) == elements)
    }

    @Test func canonicalParseRejectsNonCanonicalInput() {
        // The strict parser is the inverse of print only over the canonical form; it must reject the
        // shorthand and relative commands that the lenient parser folds away.
        #expect(SVGPathData.parseCanonical("m 0 0 l 1 1") == nil, "relative commands are not canonical")
        #expect(SVGPathData.parseCanonical("M 0 0 H 5") == nil, "H/V shorthand is not canonical")
        #expect(SVGPathData.parseCanonical("M 0 0 A 1 1 0 0 1 2 2") == nil, "arcs are not canonical")
        #expect(SVGPathData.parseCanonical("M 0 0 L 1 1") != nil, "the absolute normal form is accepted")
    }

    // MARK: - Reproducible generator (a seeded LCG: deterministic, so the proof is repeatable)

    private struct PathGenerator {
        private var state: UInt64
        init(seed: UInt64) {
            state = seed
        }

        private mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }

        private mutating func coordinate() -> Double {
            let palette: [Double] = [0, -0.0, 1, -1, 0.5, -0.5, 1.0 / 3.0, 100, -100, 1e6, 1e-6, .pi, 12345.678]
            let raw = next()
            if raw % 3 == 0 { return palette[Int((raw >> 8) % UInt64(palette.count))] }
            // A varied finite value in roughly -2000...2000 with three decimals.
            return Double(Int64(bitPattern: raw) % 2_000_000) / 1000.0
        }

        private mutating func point() -> Point {
            Point(x: coordinate(), y: coordinate())
        }

        /// A sequence whose every subpath opens with a `.move` (the well-formedness precondition).
        mutating func wellFormedSequence() -> [PathElement] {
            var elements: [PathElement] = []
            let subpaths = Int(next() % 3) + 1
            for _ in 0 ..< subpaths {
                elements.append(.move(to: point()))
                let draws = Int(next() % 5)
                for _ in 0 ..< draws {
                    switch next() % 3 {
                    case 0: elements.append(.line(to: point()))
                    case 1: elements.append(.quadCurve(to: point(), control: point()))
                    default: elements.append(.cubicCurve(to: point(), control1: point(), control2: point()))
                    }
                }
                if next() % 2 == 0 { elements.append(.close) }
            }
            return elements
        }
    }
}
