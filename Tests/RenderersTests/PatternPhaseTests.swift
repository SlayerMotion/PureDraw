//
//  PatternPhaseTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// The pattern phase anchors the tiling lattice. Rendering invariants: shifting the phase by a full
/// period leaves the image unchanged (the lattice repeats), and a partial-period shift changes it.
struct PatternPhaseTests {
    private let side = 24

    private func checkerCell() -> Pattern {
        let pattern = Pattern(bounds: Rect(x: 0, y: 0, width: 8, height: 8), isColored: true)
        pattern.context.setFillColor(Color(red: 0, green: 0, blue: 0, alpha: 1))
        pattern.context.fill(Rect(x: 0, y: 0, width: 4, height: 4))
        return pattern
    }

    private func render(phase: Point) throws -> [UInt8] {
        var context = GraphicsContext()
        context.setFillPattern(checkerCell())
        context.setPatternPhase(phase)
        context.fill(Rect(x: 0, y: 0, width: Double(side), height: Double(side)))
        return try BitmapRenderer(width: side, height: side).draw(context).data
    }

    @Test func fullPeriodPhaseIsInvisible() throws {
        let base = try render(phase: .zero)
        let shifted = try render(phase: Point(x: 8, y: 8)) // a full step in each axis
        #expect(base == shifted, "a full-period phase shift should leave the image unchanged")
    }

    @Test func partialPhaseShiftsTheImage() throws {
        let base = try render(phase: .zero)
        let shifted = try render(phase: Point(x: 4, y: 0)) // half a step
        #expect(base != shifted, "a partial phase shift should move the pattern")
    }
}
