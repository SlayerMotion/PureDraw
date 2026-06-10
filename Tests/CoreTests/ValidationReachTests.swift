//
//  ValidationReachTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing
import Validation

/// Probes whether validation reaches features added after the #53 epic.
struct ValidationReachTests {
    private func fontContext() throws -> GraphicsContext {
        var c = GraphicsContext()
        try c.setFont(Font(data: MiniFont.build()))
        c.setFontSize(10)
        return c
    }

    @Test func nonFiniteTextPositionIsCaught() throws {
        var c = try fontContext()
        c.showText("A", at: Point(x: Double.nan, y: 0))
        let result = Result { try c.validate() }
        #expect((try? result.get()) == nil, "NaN text position should fail validation")
    }

    @Test func nonFiniteTextMatrixIsCaught() throws {
        var c = try fontContext()
        c.textMatrix = AffineTransform(a: Double.infinity, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        c.showText("A", at: Point(x: 0, y: 0))
        let result = Result { try c.validate() }
        #expect((try? result.get()) == nil, "non-finite text matrix should fail validation")
    }

    @Test func negativePatternStepIsCaught() {
        let pattern = Pattern(bounds: Rect(x: 0, y: 0, width: 4, height: 4), xStep: -1, yStep: 4)
        var c = GraphicsContext()
        c.setFillPattern(pattern)
        c.addRect(Rect(x: 0, y: 0, width: 8, height: 8))
        c.fillPath()
        let result = Result { try c.validate() }
        #expect((try? result.get()) == nil, "non-positive pattern step should fail validation")
    }

    @Test func negativePatternBoundsIsCaught() {
        let pattern = Pattern(bounds: Rect(x: 0, y: 0, width: -4, height: 4))
        var c = GraphicsContext()
        c.setFillPattern(pattern)
        c.addRect(Rect(x: 0, y: 0, width: 8, height: 8))
        c.fillPath()
        let result = Result { try c.validate() }
        #expect((try? result.get()) == nil, "negative pattern bounds should fail validation")
    }
}
