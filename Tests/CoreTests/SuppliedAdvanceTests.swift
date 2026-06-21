//
//  SuppliedAdvanceTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing

/// `showGlyphs(_:advances:)` positions each glyph by a caller-supplied advance (the
/// `CGContextShowGlyphsWithAdvances` case) instead of the font's nominal advance width, so a layout
/// engine drives the run. The pen and the lowered glyph placement both follow the supplied advances.
struct SuppliedAdvanceTests {
    private func context(size: Double = 10) throws -> GraphicsContext {
        var context = GraphicsContext()
        try context.setFont(Font(data: MiniFont.build()))
        context.setFontSize(size)
        return context
    }

    @Test func suppliedAdvancesDriveThePen() throws {
        var context = try context()
        // MiniFont's 'A' has a scaled advance of 6 at this size; the caller supplies 20 and 30 instead.
        context.showGlyphs([1, 1], advances: [20, 30], at: Point(x: 5, y: 5))
        #expect(context.textPosition == Point(x: 55, y: 5)) // 5 + 20 + 30, not 5 + 6 + 6

        guard case let .showText(glyphs, _, _, _, _, _, position, advances) = context.commands[0].kind else {
            Issue.record("expected a showText operation")
            return
        }
        #expect(glyphs == [1, 1])
        #expect(position == Point(x: 5, y: 5))
        #expect(advances == [20, 30])
    }

    @Test func suppliedAdvancesPlaceLoweredGlyphs() throws {
        var context = try context()
        context.showGlyphs([1, 1], advances: [20, 30], at: Point(x: 0, y: 0))
        let lowered = context.textLoweredCommands
        // Two glyphs lower to two fills; the second is offset from the first by the first advance (20).
        let fills = lowered.compactMap { op -> Path? in
            if case let .fill(path, _) = op.kind { return path }
            return nil
        }
        #expect(fills.count == 2)
        let firstMinX = fills[0].boundingBox.minX
        let secondMinX = fills[1].boundingBox.minX
        #expect(abs((secondMinX - firstMinX) - 20) <= 1e-9, "second glyph not offset by the supplied advance")
    }

    @Test func withoutAdvancesTheFontMetricStillDrives() throws {
        var context = try context()
        context.showGlyphs([1, 1], at: Point(x: 5, y: 5))
        #expect(context.textPosition == Point(x: 17, y: 5)) // 5 + 6 + 6, the font advance
    }
}
