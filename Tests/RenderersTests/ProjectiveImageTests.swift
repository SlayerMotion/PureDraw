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

    @Test func singularTransformDrawsNothing() throws {
        let image = try solidImage(10, 255, 0, 0)
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        // A rank-deficient transform (collapses y) has no inverse; nothing should paint.
        let singular = ProjectiveTransform(m11: 1, m12: 0, m13: 0, m21: 0, m22: 0, m23: 0, m31: 0, m32: 0, m33: 1)
        #expect(ProjectiveImageRasterizer.warp(image, in: rect, transform: singular, width: 60, height: 60, quality: .default) == nil)
        var context = GraphicsContext()
        context.draw(image, in: rect, mappingTo: singular)
        let result = try BitmapRenderer(width: 60, height: 60).draw(context)
        var painted = false
        for i in stride(from: 3, to: result.data.count, by: 4) where result.data[i] > 0 {
            painted = true
            break
        }
        #expect(!painted)
    }

    @Test func straddlingTheHorizonRejectsBehindCameraPixels() throws {
        let image = try solidImage(10, 255, 0, 0)
        let rect = Rect(x: 0, y: 0, width: 40, height: 40)
        // w = 1 - 0.04*y, so the horizon is at y = 25: the rect straddles it (front for
        // y < 25, behind for y > 25). No painted device pixel may map behind the plane.
        let straddle = ProjectiveTransform(m11: 1, m12: 0, m13: 0, m21: 0, m22: 1, m23: -0.04, m31: 0, m32: 0, m33: 1)
        let warped = try #require(ProjectiveImageRasterizer.warp(image, in: rect, transform: straddle, width: 200, height: 200, quality: .default))
        let inverse = straddle.inverted()
        let centerW = straddle.m23 * 20 + straddle.m33 // 0.2 > 0
        var paintedCount = 0
        for y in 0 ..< 200 {
            for x in 0 ..< 200 where warped[(y * 200 + x) * 4 + 3] > 0 {
                paintedCount += 1
                let userPoint = Point(x: Double(x) + 0.5, y: Double(y) + 0.5).applying(inverse)
                let pointW = straddle.m13 * userPoint.x + straddle.m23 * userPoint.y + straddle.m33
                #expect((pointW > 0) == (centerW > 0)) // never behind the projection plane
            }
        }
        #expect(paintedCount > 0) // the front half still renders
    }

    @Test func partialAlphaRoundTripsAndFadesWithStateAlpha() throws {
        // A 50%-alpha red image, drawn axis-aligned, then again at state alpha 0.5.
        var data: [UInt8] = []
        for _ in 0 ..< 4 {
            data.append(contentsOf: [255, 0, 0, 128])
        } // straight alpha 0.5
        let image = try Image(width: 2, height: 2, alphaInfo: .last, data: data)
        let rect = Rect(x: 0, y: 0, width: 2, height: 2)
        let transform = ProjectiveTransform.rectToQuad(
            rect, p0: Point(x: 10, y: 10), p1: Point(x: 50, y: 10), p2: Point(x: 50, y: 50), p3: Point(x: 10, y: 50)
        )
        func centerAlpha(stateAlpha: Double) throws -> Double {
            var context = GraphicsContext()
            context.setAlpha(stateAlpha)
            context.draw(image, in: rect, mappingTo: transform)
            return try BitmapRenderer(width: 60, height: 60).draw(context).pixelColor(x: 30, y: 30).alpha
        }
        let full = try centerAlpha(stateAlpha: 1) // ~0.5 (the image's own alpha)
        let half = try centerAlpha(stateAlpha: 0.5) // ~0.25 (faded once more)
        #expect(abs(full - 0.5) < 0.05)
        #expect(abs(half - 0.25) < 0.05)
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
