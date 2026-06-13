//
//  DashStrokeTests.swift
//  PureDraw
//

import Core
import Geometry
import Renderers
import Testing

/// `BitmapRenderer` must apply `dashPattern` / `dashPhase` when stroking, so a
/// dashed line paints opaque on-spans and transparent gaps, matching the dash the
/// vector renderers already emit (issue #98).
struct DashStrokeTests {
    private func horizontalDashedLine(pattern: [Double], phase: Double) throws -> Image {
        var context = GraphicsContext()
        context.setStrokeColor(Color(red: 0, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(6)
        context.setLineCap(.butt)
        context.setLineDash(phase: phase, lengths: pattern)
        context.move(to: Point(x: 10, y: 30))
        context.addLine(to: Point(x: 90, y: 30))
        context.strokePath()
        return try BitmapRenderer(width: 100, height: 60).draw(context)
    }

    private func alpha(_ image: Image, _ x: Int, _ y: Int) -> Int {
        Int(image.data[(y * image.width + x) * 4 + 3])
    }

    @Test func dashedLinePaintsGaps() throws {
        // Pattern [10 on, 10 off] from x=10: on [10,20), off [20,30), on [30,40)...
        let image = try horizontalDashedLine(pattern: [10, 10], phase: 0)
        #expect(alpha(image, 14, 30) > 200) // first on-dash
        #expect(alpha(image, 25, 30) == 0) // first gap
        #expect(alpha(image, 35, 30) > 200) // second on-dash
        #expect(alpha(image, 45, 30) == 0) // second gap
    }

    @Test func emptyPatternStaysSolid() throws {
        // No dash: the whole line is painted, including where a gap would be.
        let image = try horizontalDashedLine(pattern: [], phase: 0)
        #expect(alpha(image, 14, 30) > 200)
        #expect(alpha(image, 25, 30) > 200)
        #expect(alpha(image, 45, 30) > 200)
    }

    @Test func phaseShiftsThePattern() throws {
        // Phase 10 starts mid-pattern in the off span, so x in [10,20) is now a gap
        // and [20,30) is on, the inverse of phase 0.
        let image = try horizontalDashedLine(pattern: [10, 10], phase: 10)
        #expect(alpha(image, 14, 30) == 0) // now a gap
        #expect(alpha(image, 25, 30) > 200) // now on
    }

    @Test func oddCountPatternRepeatsToEven() throws {
        // [10] repeats to [10, 10]: 10 on, 10 off.
        let image = try horizontalDashedLine(pattern: [10], phase: 0)
        #expect(alpha(image, 14, 30) > 200)
        #expect(alpha(image, 25, 30) == 0)
        #expect(alpha(image, 35, 30) > 200)
    }
}
