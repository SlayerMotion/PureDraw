//
//  BitmapShadowTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

struct BitmapShadowTests {
    private func rgba(_ data: [UInt8], _ x: Int, _ y: Int, width: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    @Test func transparencyLayerCastsAnOffsetShadow() throws {
        var context = GraphicsContext()
        context.setShadow(offset: Point(x: 10, y: 10), blur: 0, color: Color(red: 0, green: 0, blue: 0, alpha: 1))
        context.beginTransparencyLayer()
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.addRect(Rect(x: 10, y: 10, width: 20, height: 20))
        context.fillPath()
        context.endTransparencyLayer()

        let image = try BitmapRenderer(width: 60, height: 60).render(context)
        let data = image.data
        // Content (red) fills 10..30; the silhouette shadow is offset +10 to 20..40.
        // (35, 35) is outside the content but inside the shadow: opaque black.
        let shadow = rgba(data, 35, 35, width: 60)
        #expect(shadow.a > 0)
        #expect(shadow.r == 0 && shadow.g == 0 && shadow.b == 0)
        // (15, 15) is inside the content with no shadow beneath it: red.
        let content = rgba(data, 15, 15, width: 60)
        #expect(content.r == 255 && content.a == 255)
        // (50, 50) is outside both.
        #expect(rgba(data, 50, 50, width: 60).a == 0)
    }

    @Test func groupAlphaFadesTheShadow() throws {
        var context = GraphicsContext()
        context.setShadow(offset: Point(x: 10, y: 10), blur: 0, color: Color(red: 0, green: 0, blue: 0, alpha: 1))
        context.setAlpha(0.5) // group opacity, applied when the layer composites
        context.beginTransparencyLayer()
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.addRect(Rect(x: 10, y: 10, width: 20, height: 20))
        context.fillPath()
        context.endTransparencyLayer()

        let image = try BitmapRenderer(width: 60, height: 60).render(context)
        // The shadow fades with the group: at half group opacity its alpha is ~half.
        let shadow = rgba(image.data, 35, 35, width: 60)
        #expect(shadow.a > 110 && shadow.a < 145)
    }

    @Test func blurSpreadsTheShadowBeyondTheSilhouette() throws {
        var context = GraphicsContext()
        context.setShadow(offset: Point(x: 0, y: 0), blur: 4, color: Color(red: 0, green: 0, blue: 0, alpha: 1))
        context.beginTransparencyLayer()
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.addRect(Rect(x: 20, y: 20, width: 20, height: 20))
        context.fillPath()
        context.endTransparencyLayer()

        let image = try BitmapRenderer(width: 60, height: 60).render(context)
        let data = image.data
        // Just outside the rect edge the blur bleeds a soft shadow; without blur this
        // pixel would be empty.
        #expect(rgba(data, 42, 30, width: 60).a > 0)
        // Far from the rect stays empty.
        #expect(rgba(data, 55, 55, width: 60).a == 0)
    }
}
