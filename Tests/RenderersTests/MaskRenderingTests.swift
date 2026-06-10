//
//  MaskRenderingTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

struct MaskRenderingTests {
    @Test func grayscaleMaskClipsFill() throws {
        // Left mask column is white (reveal), right is black (hide).
        let mask = Image(
            width: 2,
            height: 1,
            bitsPerPixel: 8,
            colorSpace: .deviceGray,
            alphaInfo: .none,
            data: [255, 0]
        )

        var context = GraphicsContext()
        context.clip(to: Rect(x: 0, y: 0, width: 10, height: 10), mask: mask)
        context.setFillColor(Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
        context.addRect(Rect(x: 0, y: 0, width: 10, height: 10))
        context.fillPath()

        let image = try BitmapRenderer(width: 10, height: 10).render(context)
        let data = image.data

        for y in 0 ..< 10 {
            for x in 0 ..< 10 {
                let index = (y * 10 + x) * 4
                if x < 5 {
                    #expect(data[index] == 255, "expected red at (\(x), \(y))")
                    #expect(data[index + 3] == 255, "expected opaque at (\(x), \(y))")
                } else {
                    #expect(data[index + 3] == 0, "expected masked-out pixel at (\(x), \(y))")
                }
            }
        }
    }

    @Test func alphaMaskUsesAlphaChannel() throws {
        // Both mask pixels are white, but the right one is fully transparent.
        let mask = Image(
            width: 2,
            height: 1,
            alphaInfo: .last,
            data: [255, 255, 255, 255, 255, 255, 255, 0]
        )

        var context = GraphicsContext()
        context.clip(to: Rect(x: 0, y: 0, width: 10, height: 10), mask: mask)
        context.setFillColor(Color(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0))
        context.addRect(Rect(x: 0, y: 0, width: 10, height: 10))
        context.fillPath()

        let image = try BitmapRenderer(width: 10, height: 10).render(context)
        let data = image.data

        let leftIndex = (5 * 10 + 2) * 4
        let rightIndex = (5 * 10 + 7) * 4
        #expect(data[leftIndex + 1] == 255)
        #expect(data[leftIndex + 3] == 255)
        #expect(data[rightIndex + 3] == 0)
    }

    @Test func pixelsOutsideMaskRectAreHidden() throws {
        let mask = Image(
            width: 1,
            height: 1,
            bitsPerPixel: 8,
            colorSpace: .deviceGray,
            alphaInfo: .none,
            data: [255]
        )

        var context = GraphicsContext()
        context.clip(to: Rect(x: 0, y: 0, width: 4, height: 4), mask: mask)
        context.setFillColor(Color(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0))
        context.addRect(Rect(x: 0, y: 0, width: 10, height: 10))
        context.fillPath()

        let image = try BitmapRenderer(width: 10, height: 10).render(context)
        let data = image.data

        let insideIndex = (2 * 10 + 2) * 4
        let outsideIndex = (8 * 10 + 8) * 4
        #expect(data[insideIndex + 2] == 255)
        #expect(data[insideIndex + 3] == 255)
        #expect(data[outsideIndex + 3] == 0)
    }

    @Test func maskRespectsTransformAtClipTime() throws {
        // The mask is anchored where the CTM was when clip(to:mask:) was called;
        // a translation applied afterwards must not move the mask.
        let mask = Image(
            width: 1,
            height: 1,
            bitsPerPixel: 8,
            colorSpace: .deviceGray,
            alphaInfo: .none,
            data: [255]
        )

        var context = GraphicsContext()
        context.clip(to: Rect(x: 0, y: 0, width: 5, height: 10), mask: mask)
        context.translate(by: 5, 0)
        context.setFillColor(Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
        context.addRect(Rect(x: -5, y: 0, width: 10, height: 10))
        context.fillPath()

        let image = try BitmapRenderer(width: 10, height: 10).render(context)
        let data = image.data

        let insideIndex = (5 * 10 + 2) * 4
        let outsideIndex = (5 * 10 + 7) * 4
        #expect(data[insideIndex + 3] == 255)
        #expect(data[outsideIndex + 3] == 0)
    }

    @Test func maskingColorsAffectDrawnImages() throws {
        // Two-pixel source image: white (masked out) and blue (kept).
        let source = Image(
            width: 2,
            height: 1,
            alphaInfo: .noneSkipLast,
            maskingColors: [0.9, 1.0, 0.9, 1.0, 0.9, 1.0],
            data: [255, 255, 255, 0, 0, 0, 255, 0]
        )

        var context = GraphicsContext()
        context.draw(source, in: Rect(x: 0, y: 0, width: 10, height: 10))

        let image = try BitmapRenderer(width: 10, height: 10).render(context)
        let data = image.data

        let leftIndex = (5 * 10 + 2) * 4
        let rightIndex = (5 * 10 + 7) * 4
        #expect(data[leftIndex + 3] == 0, "white source pixel should be masked out")
        #expect(data[rightIndex + 2] == 255, "blue source pixel should draw")
        #expect(data[rightIndex + 3] == 255)
    }

    @Test func renderRejectsInvalidContext() {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 2.0, green: 0.0, blue: 0.0))
        context.addRect(Rect(x: 0, y: 0, width: 5, height: 5))
        context.fillPath()

        #expect(throws: (any Error).self) {
            try BitmapRenderer(width: 10, height: 10).render(context)
        }
        #expect(throws: (any Error).self) {
            try SVGRenderer().render(context)
        }
    }
}
