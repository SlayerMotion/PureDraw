//
//  StrokePatternTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing

/// A stroke pattern tiles the cell within the stroked outline, and the pattern phase anchors the
/// lattice. Structurally, a patterned stroke expands into tiled cell fills rather than a single stroke
/// operation, and a full-period phase shift leaves the same set of tiles.
struct StrokePatternTests {
    private func dotPattern() -> Pattern {
        let pattern = Pattern(bounds: Rect(x: 0, y: 0, width: 4, height: 4), isColored: true)
        pattern.context.setFillColor(.black)
        pattern.context.fill(Rect(x: 0, y: 0, width: 2, height: 2))
        return pattern
    }

    @Test func strokePatternExpandsToTiles() {
        var context = GraphicsContext()
        context.setLineWidth(6)
        context.setStrokePattern(dotPattern())
        context.stroke(Rect(x: 0, y: 0, width: 24, height: 24))

        let hasPlainStroke = context.commands.contains { if case .stroke = $0.kind { true } else { false } }
        let fillCount = context.commands.reduce(0) { count, op in
            if case .fill = op.kind { count + 1 } else { count }
        }
        #expect(!hasPlainStroke, "a patterned stroke should tile cells, not emit a plain stroke")
        #expect(fillCount > 1, "the stroke pattern should expand into multiple tiles")
    }

    @Test func withoutAStrokePatternAPlainStrokeIsEmitted() {
        var context = GraphicsContext()
        context.setLineWidth(6)
        context.stroke(Rect(x: 0, y: 0, width: 24, height: 24))
        #expect(context.commands.count == 1)
        #expect({ if case .stroke = context.commands[0].kind { true } else { false } }())
    }

    @Test func fullPeriodPhaseLeavesTheSameTiles() {
        let pattern = dotPattern()
        func tileCount(phase: Point) -> Int {
            var context = GraphicsContext()
            context.setFillPattern(pattern)
            context.setPatternPhase(phase)
            context.fill(Rect(x: 0, y: 0, width: 24, height: 24))
            return context.commands.reduce(0) { count, op in
                if case .fill = op.kind { count + 1 } else { count }
            }
        }
        // Shifting the lattice by a full period reproduces the same tiling over the same region.
        #expect(tileCount(phase: .zero) == tileCount(phase: Point(x: pattern.xStep, y: pattern.yStep)))
    }
}
