//
//  TextClipTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// The text-clip drawing modes turn the glyph outlines into a clip, so painting through them lands only
/// inside the letters. The defining invariant: filling the whole canvas through a `.clip` text run is
/// the same picture as filling that text directly with the same colour, since both paint the glyph
/// shape and nothing else.
struct TextClipTests {
    private let side = 100

    private func context(mode: TextDrawingMode) throws -> GraphicsContext {
        var context = GraphicsContext()
        try context.setFont(Font(data: SVGTextTests.miniFontBytes))
        context.setFontSize(100)
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.setTextDrawingMode(mode)
        return context
    }

    private func alpha(_ image: Image) -> [Double] {
        let bytesPerPixel = image.data.count / (image.width * image.height)
        return (0 ..< image.width * image.height).map { Double(image.data[$0 * bytesPerPixel + (bytesPerPixel - 1)]) / 255.0 }
    }

    @Test func fillingThroughTextClipEqualsFillingTheText() throws {
        // Fill the glyph directly.
        var fillContext = try context(mode: .fill)
        fillContext.showText("A", at: Point(x: 10, y: 60))
        let filled = try BitmapRenderer(width: side, height: side).draw(fillContext)

        // Set the glyph as a clip, then flood the whole canvas: only the letter survives.
        var clipContext = try context(mode: .clip)
        clipContext.showText("A", at: Point(x: 10, y: 60))
        clipContext.fill(Rect(x: 0, y: 0, width: Double(side), height: Double(side)))
        let clipped = try BitmapRenderer(width: side, height: side).draw(clipContext)

        let a = alpha(filled)
        let b = alpha(clipped)
        let mad = zip(a, b).reduce(0.0) { $0 + abs($1.0 - $1.1) } / Double(a.count)
        #expect(mad <= 0.02, "fill-through-clip differs from direct fill: mean absolute difference \(mad)")

        // The flood paints inside the glyph and nowhere else.
        #expect(b.contains { $0 > 0.5 }, "the text clip painted nothing")
        #expect(b.contains { $0 < 0.5 }, "the text clip painted everywhere (clip not applied)")
        // A corner well outside the 'A' square is untouched.
        #expect(b[(side - 5) * side + (side - 5)] == 0, "drawing escaped the text clip")
    }

    @Test func clipModeDoesNotPaintTheTextItself() throws {
        // `.clip` alone paints nothing (like invisible); it only sets the clip.
        var context = try context(mode: .clip)
        context.showText("A", at: Point(x: 10, y: 60))
        let image = try BitmapRenderer(width: side, height: side).draw(context)
        #expect(alpha(image).allSatisfy { $0 == 0 }, "clip mode painted the text")
    }

    @Test func fillClipPaintsTheTextAndClipsSubsequentDrawing() throws {
        // `.fillClip` paints the glyph (so the canvas is not empty) and also clips.
        var context = try context(mode: .fillClip)
        context.showText("A", at: Point(x: 10, y: 60))
        let painted = try BitmapRenderer(width: side, height: side).draw(context)
        #expect(alpha(painted).contains { $0 > 0.5 }, "fillClip did not paint the glyph")
    }
}
