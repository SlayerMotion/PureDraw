//
//  AnimatedPNGTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

struct AnimatedPNGTests {
    private func frame(_ red: Double, _ green: Double, _ blue: Double) throws -> Image {
        var context = GraphicsContext()
        context.setFillColor(Color(red: red, green: green, blue: blue, alpha: 1))
        context.fill(Rect(x: 0, y: 0, width: 4, height: 4))
        return try BitmapRenderer(width: 4, height: 4).draw(context)
    }

    private func contains(_ bytes: [UInt8], _ type: String) -> Bool {
        let needle = Array(type.utf8)
        guard bytes.count >= needle.count else { return false }
        for start in 0 ... (bytes.count - needle.count) where Array(bytes[start ..< start + needle.count]) == needle {
            return true
        }
        return false
    }

    /// Reads the big-endian num_frames field that follows the acTL type marker.
    private func numFrames(_ bytes: [UInt8]) -> Int? {
        let needle = Array("acTL".utf8)
        guard bytes.count >= needle.count else { return nil }
        for start in 0 ... (bytes.count - needle.count) where Array(bytes[start ..< start + needle.count]) == needle {
            let field = start + needle.count
            guard field + 4 <= bytes.count else { return nil }
            return (Int(bytes[field]) << 24) | (Int(bytes[field + 1]) << 16) | (Int(bytes[field + 2]) << 8) | Int(bytes[field + 3])
        }
        return nil
    }

    @Test func animatedPNGCarriesAnimationChunks() throws {
        let frames = try [frame(1, 0, 0), frame(0, 1, 0), frame(0, 0, 1)]
        let png = PNGEncoder.encodeAnimated(frames, frameDelay: 0.1)
        #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10]) // PNG signature
        #expect(contains(png, "IHDR"))
        #expect(numFrames(png) == 3)
        #expect(contains(png, "fcTL"))
        #expect(contains(png, "fdAT"))
        #expect(contains(png, "IEND"))
    }

    @Test func singleFrameFallsBackToPlainPNG() throws {
        let png = try PNGEncoder.encodeAnimated([frame(1, 0, 0)], frameDelay: 0.1)
        #expect(contains(png, "IDAT"))
        #expect(!contains(png, "acTL"))
    }

    @Test func emptyFramesProduceNoData() {
        #expect(PNGEncoder.encodeAnimated([], frameDelay: 0.1).isEmpty)
    }
}
