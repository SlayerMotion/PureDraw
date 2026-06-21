//
//  ImageMaskTests.swift
//  PureDraw
//

@testable import Core
import Testing

/// `Image.masked(by:)` bakes a mask into an image's alpha, the analog of `CGImageCreateWithMask`. A soft
/// mask multiplies the alpha by the mask coverage; the Core Graphics image mask inverts it (dark paints,
/// light blocks). The colour is preserved either way.
struct ImageMaskTests {
    /// A solid opaque red image.
    private func redImage(_ side: Int = 2) throws -> Image {
        try Image(width: side, height: side, data: [UInt8](repeating: 0, count: side * side * 4).enumerated().map { index, _ in
            switch index % 4 {
            case 0: 255 // premultiplied red
            case 3: 255 // alpha
            default: 0
            }
        })
    }

    /// A uniform grey mask of the given 0...255 level, no alpha (luminance is the coverage).
    private func greyMask(_ level: UInt8, side: Int = 2) throws -> Image {
        try Image(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
            colorSpace: .deviceGray, alphaInfo: .none, data: [UInt8](repeating: level, count: side * side)
        )
    }

    @Test func softMaskMultipliesAlphaAndKeepsColour() throws {
        let source = try redImage()
        let masked = try #require(source.masked(by: greyMask(128)))
        let pixel = masked.pixelColor(x: 0, y: 0)
        // A half-luminance mask roughly halves the alpha; the red is untouched.
        #expect(abs(pixel.alpha - 128.0 / 255.0) <= 0.01)
        #expect(abs(pixel.red - 1) <= 0.01)
        #expect(pixel.green == 0)
    }

    @Test func fullAndZeroMasks() throws {
        let source = try redImage()
        let opaque = try #require(source.masked(by: greyMask(255)))
        #expect(abs(opaque.pixelColor(x: 0, y: 0).alpha - 1) <= 0.01) // a white soft mask reveals fully
        let clear = try #require(source.masked(by: greyMask(0)))
        #expect(clear.pixelColor(x: 0, y: 0).alpha == 0) // a black soft mask hides fully
    }

    @Test func imageMaskInvertsTheConvention() throws {
        let source = try redImage()
        // As an image mask, a dark mask paints (alpha near 1) and a light mask blocks (alpha near 0).
        let painted = try #require(source.masked(by: greyMask(0), asImageMask: true))
        #expect(abs(painted.pixelColor(x: 0, y: 0).alpha - 1) <= 0.01)
        let blocked = try #require(source.masked(by: greyMask(255), asImageMask: true))
        #expect(blocked.pixelColor(x: 0, y: 0).alpha == 0)
    }
}
