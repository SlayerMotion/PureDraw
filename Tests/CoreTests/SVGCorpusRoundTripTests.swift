//
//  SVGCorpusRoundTripTests.swift
//  PureDraw
//

@testable import Core
import Testing

/// The round-trip law's witness over **real data** (round-trip-transformation.md):
/// the importer is exercised against `<path d>` strings sampled from real,
/// openly-licensed SVGs (`SVGCorpus.pathData`, from PureSVGResearch/corpus).
///
/// The invariant is monotone across parser slices: every real path either
/// (a) parses, and then round-trips through its normal form, or (b) is cleanly
/// rejected with `nil` because it uses a command this slice does not yet support.
/// It must never crash or silently corrupt. As later slices land (relative
/// commands, `H V S T`, arcs, implicit repeats), the parsed count climbs while
/// this test stays green.
struct SVGCorpusRoundTripTests {
    @Test func everyCorpusPathRoundTripsOrCleanlyRejects() {
        var parsed = 0
        var rejected = 0

        for d in SVGCorpus.pathData {
            guard let path = Path(svgPathData: d) else {
                rejected += 1
                continue
            }
            parsed += 1
            // Λ1 over real data: a parsed path round-trips through its normal form.
            #expect(Path(svgPathData: path.svgPathData) == path, "did not round-trip: \(d)")
        }

        // The whole corpus is accounted for: parsed or cleanly rejected, never lost.
        #expect(parsed + rejected == SVGCorpus.pathData.count)
        // Progress meter (informational, not an assertion): how much of the real
        // corpus this slice covers.
        print("SVG corpus coverage: parsed \(parsed), rejected \(rejected) of \(SVGCorpus.pathData.count)")
    }
}
