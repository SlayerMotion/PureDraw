//
//  AlphaOnlyImageTests.swift
//  PureDraw
//

@testable import Core
import Testing

/// An alpha-only image is a single alpha channel with no color: each sample is an alpha value and the
/// color is black. This is the `CGImageAlphaInfo.alphaOnly` layout, the natural form for a coverage or
/// mask buffer.
struct AlphaOnlyImageTests {
    @Test func eachSampleIsAlphaOverBlack() throws {
        let image = try Image(
            width: 3, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
            colorSpace: .deviceGray, alphaInfo: .alphaOnly, data: [0, 128, 255]
        )
        for x in 0 ..< 3 {
            let color = image.pixelColor(x: x, y: 0)
            #expect(color.red == 0)
            #expect(color.green == 0)
            #expect(color.blue == 0)
        }
        #expect(image.pixelColor(x: 0, y: 0).alpha == 0)
        #expect(abs(image.pixelColor(x: 1, y: 0).alpha - 128.0 / 255.0) <= 0.01)
        #expect(image.pixelColor(x: 2, y: 0).alpha == 1)
    }

    @Test func sixteenBitAlphaOnlyDecodes() throws {
        // A 16-bit alpha-only sample of 0x8000 is 32768/65535.
        let image = try Image(
            width: 1, height: 1, bitsPerComponent: 16, bitsPerPixel: 16,
            colorSpace: .deviceGray, alphaInfo: .alphaOnly, data: [0x80, 0x00]
        )
        #expect(abs(image.pixelColor(x: 0, y: 0).alpha - 32768.0 / 65535.0) <= 1e-4)
    }

    @Test func alphaOnlyHasAlphaButNoPremultiplyOrFirst() {
        #expect(AlphaInfo.alphaOnly.hasAlpha)
        #expect(AlphaInfo.alphaOnly.isAlphaOnly)
        #expect(!AlphaInfo.alphaOnly.isPremultiplied)
        #expect(!AlphaInfo.alphaOnly.isAlphaFirst)
    }

    @Test func alphaOnlyDrivesMaskCoverage() throws {
        // An alpha-only image used as a mask reports its sample as coverage.
        let image = try Image(
            width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
            colorSpace: .deviceGray, alphaInfo: .alphaOnly, data: [0, 255]
        )
        #expect(image.maskCoverage(x: 0, y: 0) == 0)
        #expect(image.maskCoverage(x: 1, y: 0) == 1)
    }
}
