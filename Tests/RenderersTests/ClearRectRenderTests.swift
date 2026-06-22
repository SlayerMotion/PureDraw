//
//  ClearRectRenderTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// `clear(_:)` is a Porter-Duff clear: after filling a region opaque, clearing a
/// sub-rectangle must drive those pixels back to fully transparent while leaving
/// the rest opaque. This proves the clear blend reaches the rasterizer, not just
/// the recorded operation.
struct ClearRectRenderTests {
    private let side = 8

    private func alpha(_ data: [UInt8], x: Int, y: Int) -> UInt8 {
        data[(y * side + x) * 4 + 3]
    }

    @Test func clearMakesCoveredPixelsTransparent() throws {
        var context = GraphicsContext()
        context.setFillColor(.black)
        context.fill(Rect(x: 0, y: 0, width: Double(side), height: Double(side)))
        context.clear(Rect(x: 2, y: 2, width: 4, height: 4))

        let data = try BitmapRenderer(width: side, height: side).draw(context).data

        // Inside the cleared rectangle: transparent.
        #expect(alpha(data, x: 3, y: 3) == 0)
        #expect(alpha(data, x: 5, y: 5) == 0)
        // Outside it: still the opaque fill.
        #expect(alpha(data, x: 0, y: 0) == 255)
        #expect(alpha(data, x: 7, y: 7) == 255)
    }

    @Test func clearRespectsTheClip() throws {
        var context = GraphicsContext()
        context.setFillColor(.black)
        context.fill(Rect(x: 0, y: 0, width: Double(side), height: Double(side)))
        // Confine clearing to the left half; the clear rect spans the whole width.
        context.clip(to: Rect(x: 0, y: 0, width: 4, height: Double(side)))
        context.clear(Rect(x: 0, y: 0, width: Double(side), height: Double(side)))

        let data = try BitmapRenderer(width: side, height: side).draw(context).data

        // Left of the clip: cleared. Right of it: the clip blocked the clear.
        #expect(alpha(data, x: 1, y: 4) == 0)
        #expect(alpha(data, x: 6, y: 4) == 255)
    }
}
