//
//  ImageCropTests.swift
//  PureDraw
//

@testable import Core
import Testing

struct ImageCropTests {
    /// A 3x2 RGBA image whose pixels encode their (x, y) so a crop can be checked
    /// against the source coordinates: red = x * 10, green = y * 10.
    private func grid() throws -> Image {
        var data: [UInt8] = []
        for y in 0 ..< 2 {
            for x in 0 ..< 3 {
                data.append(contentsOf: [UInt8(x * 10), UInt8(y * 10), 0, 255])
            }
        }
        return try Image(width: 3, height: 2, alphaInfo: .last, data: data)
    }

    @Test func cropsTheRequestedSubRectangle() throws {
        let source = try grid()
        let cropped = try #require(source.cropped(x: 1, y: 0, width: 2, height: 2))
        #expect(cropped.width == 2 && cropped.height == 2)
        #expect(cropped.bytesPerRow == 8) // tightened to the new width
        // The crop's (0,0) is the source's (1,0), and (1,1) is the source's (2,1).
        #expect(cropped.pixelColor(x: 0, y: 0).red == source.pixelColor(x: 1, y: 0).red)
        #expect(cropped.pixelColor(x: 1, y: 1).red == source.pixelColor(x: 2, y: 1).red)
        #expect(cropped.pixelColor(x: 1, y: 1).green == source.pixelColor(x: 2, y: 1).green)
    }

    @Test func clampsAPartlyOutOfBoundsRectangle() throws {
        // Requesting beyond the right/bottom edge yields only the overlapping part.
        let source = try grid()
        let cropped = try #require(source.cropped(x: 2, y: 1, width: 5, height: 5))
        #expect(cropped.width == 1 && cropped.height == 1)
        #expect(cropped.pixelColor(x: 0, y: 0).red == source.pixelColor(x: 2, y: 1).red)
    }

    @Test func clampsANegativeOrigin() throws {
        // A negative origin clamps to 0; only the in-bounds remainder is returned.
        let source = try grid()
        let cropped = try #require(source.cropped(x: -1, y: -1, width: 2, height: 2))
        #expect(cropped.width == 1 && cropped.height == 1)
        #expect(cropped.pixelColor(x: 0, y: 0).red == source.pixelColor(x: 0, y: 0).red)
    }

    @Test func returnsNilForANonOverlappingOrEmptyRectangle() throws {
        let image = try grid()
        #expect(image.cropped(x: 3, y: 0, width: 4, height: 2) == nil) // fully right of the image
        #expect(image.cropped(x: 0, y: 2, width: 3, height: 4) == nil) // fully below the image
        #expect(image.cropped(x: 0, y: 0, width: 0, height: 2) == nil) // empty width
    }

    @Test func preservesPixelLayout() throws {
        let cropped = try #require(grid().cropped(x: 0, y: 0, width: 2, height: 1))
        #expect(cropped.bitsPerPixel == 32)
        #expect(cropped.bitsPerComponent == 8)
        #expect(cropped.colorSpace == .deviceRGB)
        #expect(cropped.alphaInfo == .last)
    }

    @Test func cropsAcrossRowPaddingCorrectly() throws {
        // A 2x2 RGBA image with 8 bytes of trailing padding per row (bytesPerRow 16,
        // not 8). The crop must follow the stride, not assume tight packing.
        var data: [UInt8] = []
        for y in 0 ..< 2 {
            for x in 0 ..< 2 {
                data.append(contentsOf: [UInt8(x + 1), UInt8(y + 1), 0, 255])
            }
            data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // row padding
        }
        let padded = try Image(width: 2, height: 2, bytesPerRow: 16, alphaInfo: .last, data: data)
        let cropped = try #require(padded.cropped(x: 1, y: 0, width: 1, height: 2))
        #expect(cropped.width == 1 && cropped.height == 2)
        #expect(cropped.bytesPerRow == 4) // tight, padding dropped
        #expect(cropped.pixelColor(x: 0, y: 0).red == padded.pixelColor(x: 1, y: 0).red)
        #expect(cropped.pixelColor(x: 0, y: 1).green == padded.pixelColor(x: 1, y: 1).green)
    }

    @Test func overflowingRequestReturnsNilWithoutTrapping() throws {
        // A far edge that overflows Int must clamp, not crash.
        let image = try grid()
        let cropped = try #require(image.cropped(x: 1, y: 0, width: Int.max, height: Int.max))
        #expect(cropped.width == 2 && cropped.height == 2) // clamped to the image
        #expect(image.cropped(x: Int.max, y: 0, width: Int.max, height: 1) == nil)
    }

    @Test func preservesPremultipliedAlpha() throws {
        // Premultiplied red at 50% alpha: raw bytes (128, 0, 0, 128). The crop must
        // copy the raw bytes so the un-premultiply in pixelColor still recovers red.
        let source = try Image(width: 2, height: 1, alphaInfo: .premultipliedLast, data: [128, 0, 0, 128, 0, 0, 0, 0])
        let cropped = try #require(source.cropped(x: 0, y: 0, width: 1, height: 1))
        #expect(cropped.alphaInfo == .premultipliedLast)
        let color = cropped.pixelColor(x: 0, y: 0)
        #expect(color.red == 1.0)
        #expect(abs(color.alpha - 128.0 / 255.0) < 0.001)
    }

    @Test func fullImageCropRoundTripsEveryPixel() throws {
        let source = try grid()
        let cropped = try #require(source.cropped(x: 0, y: 0, width: 3, height: 2))
        #expect(cropped.width == 3 && cropped.height == 2)
        #expect(cropped.data == source.data)
    }
}
