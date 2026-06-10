//
//  ImagePixelSamplingTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing
import Validation

struct ImagePixelSamplingTests {
    @Test func straightAlphaRGBA() throws {
        let image = try Image(
            width: 1,
            height: 1,
            alphaInfo: .last,
            data: [255, 0, 0, 128]
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(color.red == 1.0)
        #expect(color.green == 0.0)
        #expect(color.blue == 0.0)
        #expect(abs(color.alpha - 128.0 / 255.0) < 0.001)
    }

    @Test func premultipliedRGBAIsUnpremultiplied() throws {
        let image = try Image(
            width: 1,
            height: 1,
            alphaInfo: .premultipliedLast,
            data: [128, 0, 0, 128]
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(abs(color.red - 1.0) < 0.01)
        #expect(abs(color.alpha - 128.0 / 255.0) < 0.001)
    }

    @Test func alphaFirstRGBA() throws {
        let image = try Image(
            width: 1,
            height: 1,
            alphaInfo: .first,
            data: [128, 0, 255, 0]
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(color.green == 1.0)
        #expect(abs(color.alpha - 128.0 / 255.0) < 0.001)
    }

    @Test func skippedAlphaByteIsOpaque() throws {
        let image = try Image(
            width: 1,
            height: 1,
            alphaInfo: .noneSkipLast,
            data: [0, 255, 0, 7]
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(color.green == 1.0)
        #expect(color.alpha == 1.0)
    }

    @Test func grayWithAndWithoutAlpha() throws {
        let opaque = try Image(
            width: 1,
            height: 1,
            bitsPerPixel: 8,
            colorSpace: .deviceGray,
            alphaInfo: .none,
            data: [51]
        )
        let opaqueColor = opaque.pixelColor(x: 0, y: 0)
        #expect(abs(opaqueColor.red - 0.2) < 0.001)
        #expect(opaqueColor.alpha == 1.0)

        let translucent = try Image(
            width: 1,
            height: 1,
            bitsPerPixel: 16,
            colorSpace: .deviceGray,
            alphaInfo: .last,
            data: [255, 128]
        )
        #expect(abs(translucent.pixelColor(x: 0, y: 0).alpha - 128.0 / 255.0) < 0.001)
    }

    @Test func cmykSampling() throws {
        let image = try Image(
            width: 1,
            height: 1,
            colorSpace: .deviceCMYK,
            alphaInfo: .none,
            data: [255, 0, 0, 0]
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(color.colorSpace == .deviceCMYK)
        #expect(color.components[0] == 1.0)
        #expect(color.alpha == 1.0)
    }

    @Test func bytesPerRowPaddingIsHonored() throws {
        // 1 pixel per row, 8 bytes per row: the second row starts at byte 8, not byte 4.
        let image = try Image(
            width: 1,
            height: 2,
            bytesPerRow: 8,
            alphaInfo: .last,
            data: [255, 0, 0, 255, 9, 9, 9, 9, 0, 0, 255, 255, 9, 9, 9, 9]
        )
        #expect(image.pixelColor(x: 0, y: 0).red == 1.0)
        #expect(image.pixelColor(x: 0, y: 1).blue == 1.0)
    }

    @Test func outOfBoundsSamplingIsClear() throws {
        let image = try Image(width: 1, height: 1, data: [255, 255, 255, 255])
        #expect(image.pixelColor(x: 5, y: 5) == .clear)
    }

    @Test func maskingColorsHideMatchingPixelsWithoutAlpha() throws {
        // White pixels are masked out, the blue pixel stays.
        let masked = try Image(
            width: 2,
            height: 1,
            alphaInfo: .noneSkipLast,
            maskingColors: [0.9, 1.0, 0.9, 1.0, 0.9, 1.0],
            data: [255, 255, 255, 0, 0, 0, 255, 0]
        )
        #expect(masked.pixelColor(x: 0, y: 0) == .clear)
        #expect(masked.pixelColor(x: 1, y: 0).blue == 1.0)
    }

    @Test func maskingColorsAreIgnoredOnAlphaImages() throws {
        // CoreGraphics only masks images without alpha; the white pixel must survive here.
        let image = try Image(
            width: 1,
            height: 1,
            alphaInfo: .last,
            maskingColors: [0.9, 1.0, 0.9, 1.0, 0.9, 1.0],
            data: [255, 255, 255, 255]
        )
        #expect(image.pixelColor(x: 0, y: 0) != .clear)
    }

    @Test func maskCoverageUsesAlphaWhenPresent() throws {
        let image = try Image(
            width: 1,
            height: 1,
            alphaInfo: .last,
            data: [0, 0, 0, 128]
        )
        #expect(abs(image.maskCoverage(x: 0, y: 0) - 128.0 / 255.0) < 0.001)
    }

    @Test func maskCoverageUsesLuminanceWithoutAlpha() throws {
        let image = try Image(
            width: 2,
            height: 1,
            alphaInfo: .noneSkipLast,
            data: [255, 255, 255, 0, 0, 0, 0, 0]
        )
        #expect(abs(image.maskCoverage(x: 0, y: 0) - 1.0) < 0.001)
        #expect(image.maskCoverage(x: 1, y: 0) == 0.0)
    }

    @Test func alphaInfoLayoutHelpers() {
        #expect(!AlphaInfo.none.hasAlpha)
        #expect(!AlphaInfo.noneSkipLast.hasAlpha)
        #expect(!AlphaInfo.noneSkipFirst.hasAlpha)
        #expect(AlphaInfo.last.hasAlpha)
        #expect(AlphaInfo.premultipliedFirst.hasAlpha)

        #expect(AlphaInfo.first.isAlphaFirst)
        #expect(AlphaInfo.noneSkipFirst.isAlphaFirst)
        #expect(!AlphaInfo.last.isAlphaFirst)

        #expect(AlphaInfo.premultipliedLast.isPremultiplied)
        #expect(!AlphaInfo.last.isPremultiplied)
    }

    @Test func maskingColorsValidation() throws {
        let data: [UInt8] = [255, 255, 255, 0]

        // Wrong component count for RGB.
        let wrongCount = try Image(
            width: 1,
            height: 1,
            alphaInfo: .noneSkipLast,
            maskingColors: [0.0, 1.0],
            data: data
        )
        #expect(throws: ValidationErrorCollection.self) {
            try wrongCount.validate()
        }

        // Out-of-range component.
        let outOfRange = try Image(
            width: 1,
            height: 1,
            alphaInfo: .noneSkipLast,
            maskingColors: [0.0, 1.5, 0.0, 1.0, 0.0, 1.0],
            data: data
        )
        #expect(throws: ValidationErrorCollection.self) {
            try outOfRange.validate()
        }

        // Masking colors on an image with alpha.
        let alphaImage = try Image(
            width: 1,
            height: 1,
            alphaInfo: .premultipliedLast,
            maskingColors: [0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
            data: data
        )
        #expect(throws: ValidationErrorCollection.self) {
            try alphaImage.validate()
        }

        // A valid no-alpha configuration passes.
        let valid = try Image(
            width: 1,
            height: 1,
            alphaInfo: .noneSkipLast,
            maskingColors: [0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
            data: data
        )
        #expect(throws: Never.self) {
            try valid.validate()
        }
    }

    @Test func maskStateValidation() throws {
        let mask = try Image(width: 1, height: 1, data: [255, 255, 255, 255])

        // maskImage without maskRect and maskTransform is invalid.
        let incomplete = GraphicState(maskImage: mask)
        #expect(throws: ValidationErrorCollection.self) {
            try incomplete.validate()
        }

        // The full triple is valid.
        let complete = GraphicState(
            maskImage: mask,
            maskRect: Rect(x: 0, y: 0, width: 1, height: 1),
            maskTransform: .identity
        )
        #expect(throws: Never.self) {
            try complete.validate()
        }
    }
}
