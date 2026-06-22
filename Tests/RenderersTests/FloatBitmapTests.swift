//
//  FloatBitmapTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// The float bitmap output mode composites at full precision and emits a 32-bit-float-per-component
/// image. These assert the output format decodes correctly, a solid color round-trips exactly, and a
/// smooth gradient keeps more distinct levels than the 8-bit path can (no 256-level banding), the
/// reason a float output exists.
struct FloatBitmapTests {
    @Test func floatOutputHasFloatLayout() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(Rect(x: 0, y: 0, width: 4, height: 4))

        let image = try BitmapRenderer(width: 4, height: 4, floatComponents: true).draw(context)
        #expect(image.bitsPerComponent == 32)
        #expect(image.bitsPerPixel == 128)
        #expect(image.data.count == 4 * 4 * 16)
        // The float image decodes back to the painted color.
        let color = image.pixelColor(x: 1, y: 1)
        #expect(abs(color.red - 0.3) <= 1e-5)
        #expect(abs(color.green - 0.6) <= 1e-5)
        #expect(abs(color.blue - 0.9) <= 1e-5)
    }

    @Test func eightBitOutputIsUnchanged() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(Rect(x: 0, y: 0, width: 4, height: 4))
        let image = try BitmapRenderer(width: 4, height: 4).draw(context)
        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
        #expect(image.data.count == 4 * 4 * 4)
    }

    @Test func floatGradientKeepsMorePrecisionThanBytes() throws {
        let width = 512
        let gradient = Gradient(stops: [
            GradientStop(color: Color(red: 0, green: 0, blue: 0, alpha: 1), location: 0),
            GradientStop(color: Color(red: 1, green: 1, blue: 1, alpha: 1), location: 1),
        ])
        func reds(float: Bool) throws -> [Double] {
            var context = GraphicsContext()
            context.drawLinearGradient(gradient, start: Point(x: 0, y: 0), end: Point(x: Double(width), y: 0))
            let image = try BitmapRenderer(width: width, height: 1, floatComponents: float).draw(context)
            return (0 ..< width).map { image.pixelColor(x: $0, y: 0).red }
        }

        let byteReds = try reds(float: false)
        let floatReds = try reds(float: true)

        // An 8-bit ramp can carry at most 256 distinct levels; the float ramp carries far more across
        // 512 columns, so its precision strictly exceeds the byte path's.
        let byteLevels = Set(byteReds.map { ($0 * 255).rounded() }).count
        let floatLevels = Set(floatReds).count
        #expect(byteLevels <= 256)
        #expect(floatLevels > 256)
    }
}
