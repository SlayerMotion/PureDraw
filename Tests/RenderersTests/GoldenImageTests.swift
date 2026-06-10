//
//  GoldenImageTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// Pins `BitmapRenderer` output across platforms: the same context must
/// produce byte-identical pixels on macOS, Linux, and Windows. The hashes
/// below were produced on macOS; a mismatch on another platform means the
/// rasterizer is not deterministic across toolchains, which is a bug.
struct GoldenImageTests {
    @Test func shapesAndStrokesScene() throws {
        var context = GraphicsContext()

        // Anti-aliased triangle.
        context.setFillColor(Color(red: 0.9, green: 0.2, blue: 0.1, alpha: 1.0))
        context.move(to: Point(x: 4, y: 4))
        context.addLine(to: Point(x: 30, y: 8))
        context.addLine(to: Point(x: 10, y: 28))
        context.closeSubpath()
        context.fillPath()

        // Even-odd self-overlap.
        context.setFillColor(Color(red: 0.1, green: 0.4, blue: 0.9, alpha: 0.8))
        context.addRect(Rect(x: 28, y: 4, width: 20, height: 20))
        context.addRect(Rect(x: 36, y: 12, width: 20, height: 20))
        context.fillPath(using: .evenOdd)

        // Stroked open path: miter joins, square caps, under a transform.
        context.saveGState()
        context.translate(by: 2, 30)
        context.scale(by: 1.5, 1.0)
        context.setStrokeColor(Color(red: 0.0, green: 0.6, blue: 0.3, alpha: 1.0))
        context.setLineWidth(3.0)
        context.setLineJoin(.miter)
        context.setLineCap(.square)
        context.move(to: Point(x: 2, y: 24))
        context.addLine(to: Point(x: 12, y: 4))
        context.addLine(to: Point(x: 22, y: 24))
        context.strokePath()
        context.restoreGState()

        // Aliased translucent fill on top.
        context.setShouldAntialias(false)
        context.setFillColor(Color(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.5))
        context.addEllipse(in: Rect(x: 30, y: 30, width: 28, height: 24))
        context.fillPath()

        try assertGolden(context, expected: "81fddb452a02e04e")
    }

    @Test func gradientsAndImagesScene() throws {
        var context = GraphicsContext()

        // Linear gradient under a clip.
        context.saveGState()
        context.addRect(Rect(x: 2, y: 2, width: 28, height: 28))
        context.clip()
        let linear = Gradient(stops: [
            GradientStop(color: Color(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0), location: 0.0),
            GradientStop(color: Color(red: 0.6, green: 0.0, blue: 0.6, alpha: 1.0), location: 1.0),
        ])
        context.drawLinearGradient(linear, start: Point(x: 2, y: 2), end: Point(x: 30, y: 30), options: [])
        context.restoreGState()

        // Radial gradient.
        let radial = Gradient(stops: [
            GradientStop(color: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0), location: 0.0),
            GradientStop(color: Color(red: 0.0, green: 0.2, blue: 0.7, alpha: 0.0), location: 1.0),
        ])
        context.drawRadialGradient(radial, startCenter: Point(x: 46, y: 16), startRadius: 0, endCenter: Point(x: 46, y: 16), endRadius: 14, options: [])

        // A tiny image drawn twice: interpolated and nearest.
        let sprite = try Image(width: 2, height: 2, alphaInfo: .last, data: [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 0, 255,
        ])
        context.draw(sprite, in: Rect(x: 4, y: 36, width: 24, height: 24))
        context.setInterpolationQuality(.none)
        context.draw(sprite, in: Rect(x: 34, y: 36, width: 24, height: 24))

        try assertGolden(context, expected: "6b4212db4be54c17")
    }

    @Test func masksAndLayersScene() throws {
        var context = GraphicsContext()

        // Checkerboard mask over a fill.
        let mask = try Image(
            width: 2,
            height: 2,
            bitsPerPixel: 8,
            colorSpace: .deviceGray,
            alphaInfo: .none,
            data: [255, 0, 0, 255]
        )
        context.saveGState()
        context.clip(to: Rect(x: 4, y: 4, width: 32, height: 32), mask: mask)
        context.setFillColor(Color(red: 0.8, green: 0.1, blue: 0.5, alpha: 1.0))
        context.addRect(Rect(x: 0, y: 0, width: 40, height: 40))
        context.fillPath()
        context.restoreGState()

        // Transparency layer composited with multiply at half alpha.
        context.setFillColor(Color(red: 0.9, green: 0.8, blue: 0.2, alpha: 1.0))
        context.addRect(Rect(x: 20, y: 20, width: 36, height: 36))
        context.fillPath()
        context.setAlpha(0.5)
        context.setBlendMode(.multiply)
        context.beginTransparencyLayer()
        context.setFillColor(Color(red: 0.1, green: 0.5, blue: 0.9, alpha: 1.0))
        context.addEllipse(in: Rect(x: 28, y: 28, width: 28, height: 28))
        context.fillPath()
        context.endTransparencyLayer()

        try assertGolden(context, expected: "dc1b08c41b876655")
    }

    // MARK: - Helpers

    private func assertGolden(_ context: GraphicsContext, expected: String) throws {
        let image = try BitmapRenderer(width: 64, height: 64).render(context)
        let actual = fnv1aHex(image.data)

        // The PNG form must stay encodable everywhere the hash is checked.
        let png = PNGEncoder.encode(image)
        #expect(png.count > 8)

        #expect(actual == expected, "golden hash mismatch: got \(actual), expected \(expected)")
    }

    /// FNV-1a, 64-bit, as a lowercase hex string.
    private func fnv1aHex(_ bytes: [UInt8]) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
