//
//  ClipIntersectionTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// `clip` intersects the new path with the current clip (like Core Graphics'
/// `CGContextClip`), it does not union. A gradient is bounded by the clip alone,
/// so a clip stacked on an ancestor clip must confine it to the intersection, not
/// flood the ancestor.
struct ClipIntersectionTests {
    private let gradient = Gradient(stops: [
        GradientStop(color: Color(red: 1, green: 0, blue: 0, alpha: 1), location: 0),
        GradientStop(color: Color(red: 0, green: 0, blue: 1, alpha: 1), location: 1),
    ])

    private func paintedPixels(_ image: Image) -> Int {
        var n = 0
        for i in stride(from: 3, to: image.data.count, by: 4) where image.data[i] > 0 {
            n += 1
        }
        return n
    }

    /// A gradient clipped to a small path, under an ancestor clip covering the whole
    /// canvas, paints only the small path: the stacked clip intersects the ancestor.
    @Test func gradientUnderAncestorClipIsConfinedToTheInnerPath() throws {
        var context = GraphicsContext()
        // Ancestor clip: the whole 40x40 canvas (a masksToBounds-style clip).
        context.addRect(Rect(x: 0, y: 0, width: 40, height: 40))
        context.clip()
        // Inner clip: a 20x20 path.
        context.addRect(Rect(x: 10, y: 10, width: 20, height: 20))
        context.clip()
        context.drawLinearGradient(gradient, start: Point(x: 10, y: 20), end: Point(x: 30, y: 20))

        let image = try BitmapRenderer(width: 40, height: 40).render(context)
        // Confined to the 20x20 inner path (400 px), not flooding the 40x40 canvas.
        #expect(paintedPixels(image) == 400)
        // Inside the inner path is painted; outside it (but inside the ancestor) is not.
        #expect(image.data[(20 * 40 + 20) * 4 + 3] == 255)
        #expect(image.data[(5 * 40 + 5) * 4 + 3] == 0)
    }

    /// Two partially overlapping clips: a gradient paints only their overlap.
    @Test func gradientPaintsOnlyTheOverlapOfTwoClips() throws {
        var context = GraphicsContext()
        context.addRect(Rect(x: 0, y: 0, width: 30, height: 30))
        context.clip()
        context.addRect(Rect(x: 15, y: 15, width: 30, height: 30)) // overlaps in [15,30)^2
        context.clip()
        context.drawLinearGradient(gradient, start: Point(x: 0, y: 0), end: Point(x: 40, y: 40))

        let image = try BitmapRenderer(width: 40, height: 40).render(context)
        #expect(paintedPixels(image) == 15 * 15) // only the 15x15 overlap
        #expect(image.data[(20 * 40 + 20) * 4 + 3] == 255) // in the overlap
        #expect(image.data[(5 * 40 + 5) * 4 + 3] == 0) // in the first clip only
        #expect(image.data[(35 * 40 + 35) * 4 + 3] == 0) // in the second clip only
    }

    /// A single clip still works (the common, cached path): the gradient fills it.
    @Test func singleClipStillBoundsTheGradient() throws {
        var context = GraphicsContext()
        context.addRect(Rect(x: 8, y: 8, width: 16, height: 16))
        context.clip()
        context.drawLinearGradient(gradient, start: Point(x: 8, y: 16), end: Point(x: 24, y: 16))

        let image = try BitmapRenderer(width: 40, height: 40).render(context)
        #expect(paintedPixels(image) == 16 * 16)
    }

    /// An even-odd clip masks to the even-odd region of its path: two nested rectangles wound the same
    /// way leave the inner area a hole, so a gradient bounded by the clip paints the ring but not the
    /// centre. (Regression: the clip rule was dropped, so every clip used winding.)
    @Test func evenOddClipMasksToTheEvenOddRegion() throws {
        var context = GraphicsContext()
        context.addRect(Rect(x: 10, y: 10, width: 40, height: 40)) // outer, covers [10,50)
        context.addRect(Rect(x: 20, y: 20, width: 20, height: 20)) // inner, covers [20,40)
        context.clip(using: .evenOdd)
        context.drawLinearGradient(gradient, start: Point(x: 10, y: 30), end: Point(x: 50, y: 30))

        let image = try BitmapRenderer(width: 60, height: 60).render(context)
        // The ring (in the outer rect, outside the inner) is painted.
        #expect(image.data[(12 * 60 + 12) * 4 + 3] == 255)
        // The centre (inside the inner rect) is a hole under even-odd.
        #expect(image.data[(30 * 60 + 30) * 4 + 3] == 0)
    }

    /// The same two nested rectangles under the default winding clip fill the centre (winding number
    /// two is nonzero), so the rule is honored, not ignored in the other direction either.
    @Test func windingClipFillsTheNestedRegion() throws {
        var context = GraphicsContext()
        context.addRect(Rect(x: 10, y: 10, width: 40, height: 40))
        context.addRect(Rect(x: 20, y: 20, width: 20, height: 20))
        context.clip() // winding (the default)
        context.drawLinearGradient(gradient, start: Point(x: 10, y: 30), end: Point(x: 50, y: 30))

        let image = try BitmapRenderer(width: 60, height: 60).render(context)
        #expect(image.data[(30 * 60 + 30) * 4 + 3] == 255) // centre filled under winding
    }
}
