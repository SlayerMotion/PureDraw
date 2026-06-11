//
//  DropShadowTests.swift
//  PureDraw
//

@testable import Core
#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Geometry
@testable import Renderers
import Testing

struct DropShadowTests {
    private func rectPath(_ rect: Rect) -> Path {
        var path = Path()
        path.addRect(rect)
        return path
    }

    private func alpha(_ image: Image, _ x: Int, _ y: Int) -> Int {
        Int(image.data[(y * image.width + x) * 4 + 3])
    }

    @Test func dropShadowPaintsTheOffsetSilhouetteOnly() throws {
        var context = GraphicsContext()
        context.setShadow(offset: Point(x: 12, y: 12), blur: 0, color: Color(red: 0, green: 0, blue: 0, alpha: 1))
        context.drawShadow(of: rectPath(Rect(x: 10, y: 10, width: 20, height: 20)))
        let image = try BitmapRenderer(width: 60, height: 60).draw(context)
        // The shadow is the silhouette offset by (12, 12): the source rect was 10..30,
        // so the shadow covers 22..42. A point inside the offset shadow is opaque...
        #expect(alpha(image, 35, 35) > 0)
        // ...and crucially the path itself is NOT painted: nothing at the un-offset
        // source location that the offset shadow does not also cover.
        #expect(alpha(image, 14, 14) == 0)
    }

    @Test func dropShadowWithoutAShadowStateDrawsNothing() throws {
        var context = GraphicsContext()
        // No setShadow: drawShadow is a no-op.
        context.drawShadow(of: rectPath(Rect(x: 10, y: 10, width: 20, height: 20)))
        let image = try BitmapRenderer(width: 60, height: 60).draw(context)
        var anyPainted = false
        for i in stride(from: 3, to: image.data.count, by: 4) where image.data[i] > 0 {
            anyPainted = true
            break
        }
        #expect(!anyPainted)
    }

    @Test func dropShadowBlurSpreadsThePenumbra() throws {
        func shadow(blur: Double) throws -> Image {
            var context = GraphicsContext()
            context.setShadow(offset: Point(x: 0, y: 0), blur: blur, color: Color(red: 0, green: 0, blue: 0, alpha: 1))
            context.drawShadow(of: rectPath(Rect(x: 20, y: 20, width: 20, height: 20)))
            return try BitmapRenderer(width: 80, height: 80).draw(context)
        }
        // Just outside the 20..40 silhouette, a blurred shadow bleeds coverage that a
        // hard (zero-radius) shadow does not.
        let sharp = try shadow(blur: 0)
        let blurred = try shadow(blur: 6)
        #expect(alpha(sharp, 44, 30) == 0)
        #expect(alpha(blurred, 44, 30) > 0)
    }

    #if canImport(CoreGraphics)
        @Test func coreGraphicsRendererCastsADropShadow() throws {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let cgContext = CGContext(
                data: nil, width: 60, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                Issue.record("Failed to create offscreen CGContext")
                return
            }
            var context = GraphicsContext()
            context.setShadow(offset: Point(x: 8, y: 8), blur: 2, color: Color(red: 0, green: 0, blue: 0, alpha: 1))
            context.drawShadow(of: rectPath(Rect(x: 10, y: 10, width: 20, height: 20)))
            try CoreGraphicsRenderer(context: cgContext).render(context)
            // The shared software shadow was composited into the CG buffer: some pixel
            // is painted (alpha > 0), proving the CG drop-shadow path runs end to end.
            guard let raw = cgContext.data else {
                Issue.record("CGContext has no backing data")
                return
            }
            let bytesPerRow = cgContext.bytesPerRow
            let pixels = raw.bindMemory(to: UInt8.self, capacity: bytesPerRow * 60)
            var painted = 0
            for y in 0 ..< 60 {
                for x in 0 ..< 60 where pixels[y * bytesPerRow + x * 4 + 3] > 0 {
                    painted += 1
                }
            }
            #expect(painted > 0)
            // ...but not the whole canvas (a shadow, not a fill).
            #expect(painted < 60 * 60)
        }

        /// Renders a single drop shadow into a fresh premultiplied CG bitmap and
        /// returns the peak alpha byte, so the CG path can be compared to itself.
        private func cgShadowPeakAlpha(layerAlpha: Double) throws -> Int {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let cgContext = CGContext(
                data: nil, width: 60, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return -1 }
            var context = GraphicsContext()
            context.setAlpha(layerAlpha)
            context.setShadow(offset: Point(x: 8, y: 8), blur: 0, color: Color(red: 0, green: 0, blue: 0, alpha: 1))
            context.drawShadow(of: rectPath(Rect(x: 10, y: 10, width: 20, height: 20)))
            try CoreGraphicsRenderer(context: cgContext).render(context)
            guard let raw = cgContext.data else { return -1 }
            let bytesPerRow = cgContext.bytesPerRow
            let pixels = raw.bindMemory(to: UInt8.self, capacity: bytesPerRow * 60)
            var peak = 0
            for y in 0 ..< 60 {
                for x in 0 ..< 60 {
                    peak = max(peak, Int(pixels[y * bytesPerRow + x * 4 + 3]))
                }
            }
            return peak
        }

        @Test func coreGraphicsRendererAppliesLayerAlphaOnce() throws {
            // A hard (blur 0) shadow of an opaque rect is fully opaque at full alpha,
            // and ~half as opaque at alpha 0.5. If state.alpha were applied twice (once
            // baked in, once via the gstate), it would land near 0.25, not 0.5.
            let full = try cgShadowPeakAlpha(layerAlpha: 1)
            let half = try cgShadowPeakAlpha(layerAlpha: 0.5)
            #expect(full > 240)
            #expect(half > 110 && half < 145) // ~0.5 * 255, not ~0.25 * 255
        }
    #endif

    @Test func transparencyLayerShadowStillWorks() throws {
        // Regression: the existing content-silhouette shadow (refactored to share the
        // kernel) still casts from a filled shape inside a transparency layer.
        var context = GraphicsContext()
        context.setShadow(offset: Point(x: 12, y: 12), blur: 0, color: Color(red: 0, green: 0, blue: 0, alpha: 1))
        context.beginTransparencyLayer()
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(rectPath(Rect(x: 10, y: 10, width: 20, height: 20)))
        context.endTransparencyLayer()
        let image = try BitmapRenderer(width: 60, height: 60).draw(context)
        #expect(alpha(image, 35, 35) > 0) // shadow at the offset
        #expect(alpha(image, 20, 20) > 0) // the red content itself
    }
}
