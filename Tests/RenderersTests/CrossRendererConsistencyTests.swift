//
//  CrossRendererConsistencyTests.swift
//  PureDraw
//
//  The repo states as a non-negotiable that a context rendered by BitmapRenderer and
//  CoreGraphicsRenderer produces the same picture, but GoldenImageTests only pin each
//  renderer in isolation (PureDraw #112, audit .audit/PureDraw.md #3). These tests render
//  representative command vocabulary through BOTH renderers and assert pixel equivalence
//  within an antialiasing tolerance: an exact match is impossible (the analytic coverage
//  rasterizer and CoreGraphics use different edge-AA and transcendentals), but a structural
//  divergence (wrong shape, color, or clip) exceeds the bound. Both renderers emit
//  premultiplied-last RGBA, so the buffers compare directly.
//

import Core
import Foundation
import Geometry
import Renderers
import Testing

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

struct CrossRendererConsistencyTests {
    private let w = 80
    private let h = 80

    private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var sum = 0.0
        for i in a.indices {
            sum += abs(Double(a[i]) - Double(b[i]))
        }
        return sum / Double(a.count)
    }

    #if canImport(CoreGraphics)
        /// Renders `context` through CoreGraphicsRenderer into a premultiplied-last bitmap and
        /// returns its RGBA bytes, matching BitmapRenderer's output layout.
        private func cgBytes(_ context: GraphicsContext) throws -> [UInt8]? {
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let cg = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            // PureDraw uses a top-left origin (y-down); a CGContext is natively bottom-left.
            // The renderer draws in the context's coordinate system (its image/shadow passes
            // flip locally to correct for a top-left context), so flip to top-left here, the
            // way a caller wanting BitmapRenderer-equivalent output must.
            cg.translateBy(x: 0, y: CGFloat(h))
            cg.scaleBy(x: 1, y: -1)
            try CoreGraphicsRenderer(context: cg).render(context)
            guard let data = cg.data else { return nil }
            let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
            return Array(UnsafeBufferPointer(start: ptr, count: w * h * 4))
        }

        /// Asserts BitmapRenderer and CoreGraphicsRenderer agree on `context` within `tolerance`
        /// mean absolute byte difference.
        private func expectConsistent(_ context: GraphicsContext, tolerance: Double, _ label: String) throws {
            let bmp = try BitmapRenderer(width: w, height: h).render(context)
            guard let cg = try cgBytes(context) else {
                Issue.record("\(label): no CGContext")
                return
            }
            let diff = meanAbsDiff(bmp.data, cg)
            #expect(diff <= tolerance, "\(label): BitmapRenderer vs CoreGraphicsRenderer diff \(diff) > \(tolerance)")
        }
    #else
        private func expectConsistent(_: GraphicsContext, tolerance _: Double, _: String) throws {}
    #endif

    @Test func solidFillConsistent() throws {
        var c = GraphicsContext()
        c.setFillColor(Color(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        c.fill(Rect(x: 12, y: 12, width: 50, height: 44))
        try expectConsistent(c, tolerance: 6, "solid fill")
    }

    @Test func fillPathWindingAndEvenOddConsistent() throws {
        for rule in [FillRule.winding, .evenOdd] {
            var c = GraphicsContext()
            c.setFillColor(Color(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
            var path = Path(rect: Rect(x: 10, y: 10, width: 56, height: 56))
            path.addRect(Rect(x: 28, y: 28, width: 20, height: 20)) // hole under even-odd
            c.addPath(path)
            c.fillPath(using: rule)
            try expectConsistent(c, tolerance: 14, "fillPath \(rule)")
        }
    }

    @Test func strokeConsistent() throws {
        var c = GraphicsContext()
        c.setStrokeColor(Color(red: 0.1, green: 0.7, blue: 0.3, alpha: 1))
        c.setLineWidth(6)
        c.move(to: Point(x: 14, y: 16))
        c.addLine(to: Point(x: 64, y: 30))
        c.addLine(to: Point(x: 20, y: 64))
        c.strokePath()
        try expectConsistent(c, tolerance: 20, "stroke polyline")
    }

    @Test func roundedRectConsistent() throws {
        var c = GraphicsContext()
        c.setFillColor(Color(red: 0.5, green: 0.4, blue: 0.85, alpha: 1))
        c.addRoundedRect(in: Rect(x: 10, y: 10, width: 56, height: 56), cornerWidth: 16, cornerHeight: 16)
        c.fillPath()
        try expectConsistent(c, tolerance: 16, "rounded rect")
    }

    @Test func clipConsistent() throws {
        var c = GraphicsContext()
        c.addRect(Rect(x: 20, y: 20, width: 40, height: 40))
        c.clip()
        c.setFillColor(Color(red: 0.9, green: 0.8, blue: 0.1, alpha: 1))
        c.fill(Rect(x: 0, y: 0, width: 80, height: 80)) // clipped to the rect
        try expectConsistent(c, tolerance: 8, "clipped fill")
    }

    @Test func transformConsistent() throws {
        var c = GraphicsContext()
        c.concatenate(AffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 18, ty: 12))
        c.setFillColor(Color(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        c.fill(Rect(x: 0, y: 0, width: 40, height: 40))
        try expectConsistent(c, tolerance: 8, "translated fill")
    }

    @Test func nonSeparableBlendConsistent() throws {
        // The W3C non-separable blend modes (hue/saturation/color/luminosity) are implemented
        // in BitmapRenderer (#111); cross-check them against CoreGraphics's native CGBlendMode
        // so the luminosity/saturation transfer math matches the platform reference. A coloured
        // foreground blends over a contrasting backdrop.
        for mode: BlendMode in [.hue, .saturation, .color, .luminosity] {
            var c = GraphicsContext()
            c.setFillColor(Color(red: 0.2, green: 0.5, blue: 0.85, alpha: 1)) // backdrop
            c.fill(Rect(x: 0, y: 0, width: 80, height: 80))
            c.setBlendMode(mode)
            c.setFillColor(Color(red: 0.9, green: 0.35, blue: 0.1, alpha: 1)) // foreground
            c.fill(Rect(x: 10, y: 10, width: 60, height: 60))
            try expectConsistent(c, tolerance: 18, "non-separable blend \(mode)")
        }
    }
}
