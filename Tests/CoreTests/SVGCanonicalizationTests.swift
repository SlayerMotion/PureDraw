//
//  SVGCanonicalizationTests.swift
//  PureDraw
//
//  The complement to the round-trip proof. SVGPathRoundTripProofTests pins
//  parseCanonical(print(x)) == x (the canonical form survives a print/parse cycle). That is
//  necessary but not sufficient: it says nothing about REAL inputs, which arrive in
//  non-canonical SVG (relative commands, H/V shorthand, implicit repeats). This pins the
//  other direction: the lenient parser plus print must CANONICALISE such input losslessly,
//  folding it to the same absolute geometry a hand-written canonical path would have, and
//  emitting only the strict normal form. The expectation is derived by hand, not read back
//  from the parser.
//

@testable import Core
import Geometry
import Testing

struct SVGCanonicalizationTests {
    @Test func lenientParseAndPrintCanonicaliseNonCanonicalInput() throws {
        // m/l are relative; h/v are shorthand. Folded to absolute by hand:
        //   m 10 10           -> M 10 10                 (a leading relative moveto is absolute)
        //   l 20 0  from 10,10 -> L 30 10
        //   h 10    from 30,10 -> L 40 10
        //   v 10    from 40,10 -> L 40 20
        //   z                  -> Z
        let messy = "m 10 10 l 20 0 h 10 v 10 z"
        let canonicalEquivalent = "M 10 10 L 30 10 L 40 10 L 40 20 Z"

        let parsedMessy = try #require(SVGPathData.parse(messy), "the lenient parser accepts valid non-canonical input")

        // (1) It folds to the correct absolute geometry: the same elements the hand-written
        // canonical path parses to.
        #expect(parsedMessy == SVGPathData.parse(canonicalEquivalent), "relative + H/V fold to the hand-derived absolute path")

        // (2) Printing canonicalises: the output is the strict normal form (re-parses
        // identically under the canonical parser) and carries no relative/shorthand letters.
        let printed = SVGPathData.print(parsedMessy)
        #expect(SVGPathData.parseCanonical(printed) == parsedMessy, "print(parse(messy)) is in the canonical normal form")
        #expect(!printed.contains(where: { "mlhvcsqtaz".contains($0) }), "no relative/shorthand letters survive; got \(printed)")
    }
}
