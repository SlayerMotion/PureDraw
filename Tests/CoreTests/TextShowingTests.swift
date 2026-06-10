//
//  TextShowingTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing

struct TextShowingTests {
    private func makeContext(size: Double = 10) throws -> GraphicsContext {
        var context = GraphicsContext()
        try context.setFont(Font(data: MiniFont.build()))
        context.setFontSize(size)
        return context
    }

    @Test func showTextRecordsScaledFillOutlines() throws {
        var context = try makeContext()
        context.showText("AA", at: Point(x: 20, y: 20))

        #expect(context.commands.count == 2)
        guard case let .fill(first, rule) = context.commands[0].kind,
              case let .fill(second, _) = context.commands[1].kind
        else {
            Issue.record("expected two fill operations")
            return
        }
        #expect(rule == .winding)

        // 500-unit square at 10pt over 1000 upem: 5 user units, above the baseline.
        let firstBounds = first.boundingBox
        #expect(firstBounds.minX == 20 && firstBounds.maxX == 25)
        #expect(firstBounds.minY == 15 && firstBounds.maxY == 20)

        // Advance: 600 units -> 6 user units.
        let secondBounds = second.boundingBox
        #expect(secondBounds.minX == 26 && secondBounds.maxX == 31)

        #expect(context.textPosition == Point(x: 32, y: 20))
    }

    @Test func unmappedCharactersUseMissingGlyph() throws {
        var context = try makeContext()
        context.showText("B", at: Point(x: 0, y: 0))

        // Glyph 0 has no outline, so nothing is painted, but the position
        // advances by the missing glyph's width (500 units -> 5).
        #expect(context.commands.isEmpty)
        #expect(context.textPosition == Point(x: 5, y: 0))
    }

    @Test func invisibleModeOnlyAdvances() throws {
        var context = try makeContext()
        context.setTextDrawingMode(.invisible)
        context.showText("A", at: Point(x: 0, y: 0))

        #expect(context.commands.isEmpty)
        #expect(context.textPosition == Point(x: 6, y: 0))
    }

    @Test func characterSpacingExtendsAdvance() throws {
        var context = try makeContext()
        context.setCharacterSpacing(2)
        context.showText("A", at: Point(x: 0, y: 0))

        #expect(context.textPosition == Point(x: 8, y: 0))
    }

    @Test func strokeAndFillStrokeModes() throws {
        var context = try makeContext()
        context.setTextDrawingMode(.stroke)
        context.showText("A", at: Point(x: 0, y: 0))
        #expect(context.commands.count == 1)
        if case .stroke = context.commands[0].kind {} else {
            Issue.record("expected a stroke operation")
        }

        context.setTextDrawingMode(.fillStroke)
        context.showText("A", at: Point(x: 0, y: 10))
        #expect(context.commands.count == 3)
    }

    @Test func textMatrixScalesGlyphsAndAdvances() throws {
        var context = try makeContext()
        context.textMatrix = AffineTransform.identity.scaledBy(x: 2, y: 2)
        context.showText("A", at: Point(x: 20, y: 20))

        guard case let .fill(path, _) = context.commands[0].kind else {
            Issue.record("expected a fill operation")
            return
        }
        let bounds = path.boundingBox
        #expect(bounds.minX == 20 && bounds.maxX == 30)
        #expect(bounds.minY == 10 && bounds.maxY == 20)
        #expect(context.textPosition == Point(x: 32, y: 20))
    }

    @Test func showGlyphsBypassesCmap() throws {
        var context = try makeContext()
        context.showGlyphs([1], at: Point(x: 0, y: 10))
        #expect(context.commands.count == 1)
    }

    @Test func fontStateSavesAndRestores() throws {
        var context = try makeContext(size: 24)
        context.saveGState()
        context.setFontSize(48)
        context.restoreGState()
        context.showText("A", at: Point(x: 0, y: 50))

        guard case let .fill(path, _) = context.commands[0].kind else {
            Issue.record("expected a fill operation")
            return
        }
        // 24pt over 1000 upem: the square is 12 units tall.
        #expect(path.boundingBox.height == 12)
    }
}
