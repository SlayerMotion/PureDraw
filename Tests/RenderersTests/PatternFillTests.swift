//
//  PatternFillTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

struct PatternFillTests {
    /// A 4x4 cell: a 2x2 colored square in the lower-left quadrant.
    private func dotPattern(color: Color, isColored: Bool) -> Pattern {
        let pattern = Pattern(bounds: Rect(x: 0, y: 0, width: 4, height: 4), isColored: isColored)
        pattern.context.setFillColor(color)
        pattern.context.addRect(Rect(x: 0, y: 0, width: 2, height: 2))
        pattern.context.fillPath()
        return pattern
    }

    @Test func coloredPatternTilesAcrossFill() throws {
        let pattern = dotPattern(color: Color(red: 1, green: 0, blue: 0, alpha: 1), isColored: true)

        var context = GraphicsContext()
        context.setFillPattern(pattern)
        context.addRect(Rect(x: 0, y: 0, width: 8, height: 8))
        context.fillPath()

        let image = try BitmapRenderer(width: 8, height: 8).render(context)
        let data = image.data

        /// Cell dots sit at every 4-unit tile's lower-left 2x2 block.
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            data[(y * 8 + x) * 4 + 3]
        }
        func red(_ x: Int, _ y: Int) -> UInt8 {
            data[(y * 8 + x) * 4]
        }

        #expect(red(1, 1) == 255 && alpha(1, 1) == 255, "tile (0,0) dot")
        #expect(red(5, 1) == 255 && alpha(5, 1) == 255, "tile (1,0) dot")
        #expect(red(1, 5) == 255, "tile (0,1) dot")
        #expect(red(5, 5) == 255, "tile (1,1) dot")
        // Gaps between dots stay clear.
        #expect(alpha(3, 3) == 0, "gap between tiles")
        #expect(alpha(7, 7) == 0)
    }

    @Test func uncoloredPatternUsesCurrentFillColor() throws {
        // The cell paints green, but an uncolored pattern must ignore that.
        let pattern = dotPattern(color: Color(red: 0, green: 1, blue: 0, alpha: 1), isColored: false)

        var context = GraphicsContext()
        context.setFillColor(Color(red: 0, green: 0, blue: 1, alpha: 1)) // blue
        context.setFillPattern(pattern)
        context.addRect(Rect(x: 0, y: 0, width: 4, height: 4))
        context.fillPath()

        let image = try BitmapRenderer(width: 4, height: 4).render(context)
        let data = image.data

        // The dot at (1,1) must be blue (the current fill color), not green.
        let idx = (1 * 4 + 1) * 4
        #expect(data[idx + 2] == 255, "uncolored pattern should use blue fill color")
        #expect(data[idx + 1] == 0, "green cell color must be ignored")
    }

    @Test func patternClipsToFillPath() throws {
        let pattern = dotPattern(color: Color(red: 1, green: 0, blue: 0, alpha: 1), isColored: true)

        var context = GraphicsContext()
        context.setFillPattern(pattern)
        // Fill only the left half; the right half must stay clear even though
        // tiles would otherwise cover it.
        context.addRect(Rect(x: 0, y: 0, width: 4, height: 8))
        context.fillPath()

        let image = try BitmapRenderer(width: 8, height: 8).render(context)
        let data = image.data

        #expect(data[(1 * 8 + 1) * 4 + 3] == 255, "dot inside the fill")
        #expect(data[(1 * 8 + 5) * 4 + 3] == 0, "tile outside the fill path is clipped away")
    }

    @Test func clearingPatternRestoresSolidFill() throws {
        let pattern = dotPattern(color: Color(red: 1, green: 0, blue: 0, alpha: 1), isColored: true)

        var context = GraphicsContext()
        context.setFillPattern(pattern)
        context.setFillPattern(nil)
        context.setFillColor(Color(red: 0, green: 1, blue: 0, alpha: 1))
        context.addRect(Rect(x: 0, y: 0, width: 4, height: 4))
        context.fillPath()

        let image = try BitmapRenderer(width: 4, height: 4).render(context)
        let data = image.data
        // A solid green fill: the gap pixel (3,3) is painted, not clear.
        #expect(data[(3 * 4 + 3) * 4 + 1] == 255)
        #expect(data[(3 * 4 + 3) * 4 + 3] == 255)
    }
}
