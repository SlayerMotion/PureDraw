//
//  LayerTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

struct LayerTests {
    private func redSquareLayer() -> Layer {
        let layer = Layer(width: 4, height: 4)
        layer.context.setFillColor(Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
        layer.context.addRect(Rect(x: 0, y: 0, width: 4, height: 4))
        layer.context.fillPath()
        return layer
    }

    @Test func bitmapStampsLayerRepeatedly() throws {
        let layer = redSquareLayer()

        var context = GraphicsContext()
        context.draw(layer, at: Point(x: 1, y: 1))
        context.draw(layer, at: Point(x: 9, y: 9))

        let image = try BitmapRenderer(width: 16, height: 16).render(context)
        let data = image.data

        #expect(data[(2 * 16 + 2) * 4] == 255, "first stamp should paint (2, 2)")
        #expect(data[(2 * 16 + 2) * 4 + 3] == 255)
        #expect(data[(10 * 16 + 10) * 4] == 255, "second stamp should paint (10, 10)")
        #expect(data[(6 * 16 + 6) * 4 + 3] == 0, "between stamps stays clear")
    }

    @Test func bitmapScalesLayerIntoRect() throws {
        let layer = Layer(width: 4, height: 4)
        layer.context.setFillColor(Color(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0))
        layer.context.addRect(Rect(x: 0, y: 0, width: 2, height: 4)) // left half
        layer.context.fillPath()

        var context = GraphicsContext()
        context.setInterpolationQuality(.none)
        context.draw(layer, in: Rect(x: 0, y: 0, width: 8, height: 8)) // 2x scale

        let image = try BitmapRenderer(width: 8, height: 8).render(context)
        let data = image.data

        #expect(data[(1 * 8 + 1) * 4 + 2] == 255, "scaled left half should be blue")
        #expect(data[(1 * 8 + 6) * 4 + 3] == 0, "scaled right half stays clear")
    }

    @Test func vectorBackendsInlineLayerCommands() throws {
        let layer = redSquareLayer()

        var context = GraphicsContext()
        context.draw(layer, at: Point(x: 2, y: 2))
        context.draw(layer, at: Point(x: 10, y: 2))

        let svg = try SVGRenderer().render(context)
        let pathCount = svg.components(separatedBy: "<path").count - 1
        #expect(pathCount >= 2, "each stamp should inline the layer's path, got \(pathCount)")
    }

    @Test func selfReferentialLayerTerminates() throws {
        let layer = Layer(width: 8, height: 8)
        layer.context.setFillColor(Color(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0))
        layer.context.addRect(Rect(x: 0, y: 0, width: 8, height: 8))
        layer.context.fillPath()
        layer.context.draw(layer, in: Rect(x: 2, y: 2, width: 4, height: 4))

        var context = GraphicsContext()
        context.draw(layer, at: Point(x: 0, y: 0))

        // The recursion cap must end both rasterization and flattening.
        let image = try BitmapRenderer(width: 8, height: 8).render(context)
        #expect(image.data[(1 * 8 + 1) * 4 + 1] == 255)
        _ = try SVGRenderer().render(context)
    }

    @Test func coreGraphicsStampsNativeLayers() throws {
        #if canImport(CoreGraphics)
            let layer = redSquareLayer()

            var context = GraphicsContext()
            context.draw(layer, at: Point(x: 1, y: 1))
            context.draw(layer, at: Point(x: 9, y: 9))

            guard let cgContext = CGContext(
                data: nil,
                width: 16,
                height: 16,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                Issue.record("Failed to create offscreen CGContext")
                return
            }
            try CoreGraphicsRenderer(context: cgContext).render(context)

            guard let buffer = cgContext.data else {
                Issue.record("Offscreen CGContext has no backing data")
                return
            }
            let pixels = buffer.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = cgContext.bytesPerRow

            // CG is y-up: the stamp at (1, 1) lands in the bottom rows of the
            // buffer, the stamp at (9, 9) in the top rows.
            #expect(pixels[12 * bytesPerRow + 2 * 4] == 255, "stamp at (1, 1) missing")
            #expect(pixels[4 * bytesPerRow + 10 * 4] == 255, "stamp at (9, 9) missing")
            #expect(pixels[8 * bytesPerRow + 7 * 4 + 3] == 0, "between stamps stays clear")
        #endif
    }
}
