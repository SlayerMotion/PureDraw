//
//  ProjectiveImageTests.swift
//  PureDraw
//

@testable import Core
#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Geometry
@testable import Renderers
import Testing

struct ProjectiveImageTests {
    private func solidImage(_ size: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) throws -> Image {
        var data: [UInt8] = []
        for _ in 0 ..< (size * size) {
            data.append(contentsOf: [r, g, b, 255])
        }
        return try Image(width: size, height: size, alphaInfo: .last, data: data)
    }

    private func redAlpha(_ image: Image, _ x: Int, _ y: Int) -> Bool {
        let c = image.pixelColor(x: x, y: y)
        return c.alpha > 0.5 && c.red > 0.5 && c.green < 0.5 && c.blue < 0.5
    }

    private func clear(_ image: Image, _ x: Int, _ y: Int) -> Bool {
        image.pixelColor(x: x, y: y).alpha < 0.5
    }

    @Test func mapsImageOntoAnAxisAlignedQuad() throws {
        var context = GraphicsContext()
        let image = try solidImage(10, 255, 0, 0)
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        let transform = ProjectiveTransform.rectToQuad(
            rect,
            p0: Point(x: 10, y: 10), p1: Point(x: 50, y: 10),
            p2: Point(x: 50, y: 50), p3: Point(x: 10, y: 50)
        )
        context.draw(image, in: rect, mappingTo: transform)
        let result = try BitmapRenderer(width: 60, height: 60).draw(context)
        #expect(redAlpha(result, 30, 30)) // inside the quad
        #expect(clear(result, 5, 5)) // outside the quad
        #expect(clear(result, 55, 55))
    }

    @Test func warpsToAPerspectiveTrapezoid() throws {
        var context = GraphicsContext()
        let image = try solidImage(10, 255, 0, 0)
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        // A keystone: narrow top edge [20, 40], wide bottom edge [10, 50].
        let transform = ProjectiveTransform.rectToQuad(
            rect,
            p0: Point(x: 20, y: 10), p1: Point(x: 40, y: 10),
            p2: Point(x: 50, y: 50), p3: Point(x: 10, y: 50)
        )
        context.draw(image, in: rect, mappingTo: transform)
        let result = try BitmapRenderer(width: 60, height: 60).draw(context)
        #expect(redAlpha(result, 30, 45)) // inside the wide bottom
        #expect(clear(result, 12, 15)) // top is narrow, so this corner is cut away
    }

    #if canImport(CoreGraphics)
        @Test func coreGraphicsMatchesTheSoftwareWarp() throws {
            let image = try solidImage(10, 255, 0, 0)
            let rect = Rect(x: 0, y: 0, width: 10, height: 10)
            let transform = ProjectiveTransform.rectToQuad(
                rect,
                p0: Point(x: 10, y: 10), p1: Point(x: 50, y: 10),
                p2: Point(x: 50, y: 50), p3: Point(x: 10, y: 50)
            )
            var context = GraphicsContext()
            context.draw(image, in: rect, mappingTo: transform)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let cgContext = CGContext(
                data: nil, width: 60, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                Issue.record("Failed to create offscreen CGContext")
                return
            }
            try CoreGraphicsRenderer(context: cgContext).render(context)
            guard let raw = cgContext.data else {
                Issue.record("CGContext has no backing data")
                return
            }
            let bytesPerRow = cgContext.bytesPerRow
            let pixels = raw.bindMemory(to: UInt8.self, capacity: bytesPerRow * 60)
            // Same structural picture as the software warp: opaque inside the quad,
            // transparent outside.
            #expect(pixels[30 * bytesPerRow + 30 * 4 + 3] > 0)
            #expect(pixels[5 * bytesPerRow + 5 * 4 + 3] == 0)
        }
    #endif
}
