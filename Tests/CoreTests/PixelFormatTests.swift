//
//  PixelFormatTests.swift
//  PureDraw
//

@testable import Core
import Testing

/// Wider bitmap component formats: 16-bit and 32-bit-float per component, and the decode array's
/// per-component affine remap. The decode is derived from first principles: an n-bit sample is the
/// integer divided by `2^n - 1`, a float sample is the IEEE value itself, and the decode array maps
/// `[0, 1]` onto `[min, max]` per color component (never alpha).
struct PixelFormatTests {
    private func approx(_ a: Double, _ b: Double, tol: Double = 1e-4) -> Bool {
        abs(a - b) <= tol
    }

    private func u16BE(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func floatLE(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
        ]
    }

    @Test func sixteenBitRGBDecodesByDivisionBy65535() throws {
        // R = 32768/65535, G = 65535/65535, B = 0; big-endian, no alpha.
        let data = u16BE(32768) + u16BE(65535) + u16BE(0)
        let image = try Image(
            width: 1, height: 1, bitsPerComponent: 16, bitsPerPixel: 48,
            colorSpace: .deviceRGB, alphaInfo: .none, data: data
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(approx(color.red, 32768.0 / 65535.0))
        #expect(approx(color.green, 1.0))
        #expect(approx(color.blue, 0.0))
    }

    @Test func sixteenBitStraightAlphaIsDecoded() throws {
        // RGBA16, straight alpha last: R = 1, G = 0, B = 0, A = 0.5.
        let data = u16BE(65535) + u16BE(0) + u16BE(0) + u16BE(32768)
        let image = try Image(
            width: 1, height: 1, bitsPerComponent: 16, bitsPerPixel: 64,
            colorSpace: .deviceRGB, alphaInfo: .last, data: data
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(approx(color.red, 1.0))
        #expect(approx(color.alpha, 32768.0 / 65535.0))
    }

    @Test func floatComponentsDecodeToTheirValue() throws {
        let data = floatLE(0.25) + floatLE(0.5) + floatLE(0.75)
        let image = try Image(
            width: 1, height: 1, bitsPerComponent: 32, bitsPerPixel: 96,
            colorSpace: .deviceRGB, alphaInfo: .none, data: data
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(approx(color.red, 0.25))
        #expect(approx(color.green, 0.5))
        #expect(approx(color.blue, 0.75))
    }

    @Test func decodeArrayInvertsAComponent() throws {
        // 8-bit gray 0.25, decode [1, 0] inverts to 1 - 0.25 = 0.75.
        let image = try Image(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
            colorSpace: .deviceGray, alphaInfo: .none, decode: [1.0, 0.0], data: [64]
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(approx(color.red, 0.75, tol: 0.01))
    }

    @Test func decodeArrayRemapsOntoARange() throws {
        // 8-bit gray 1.0 with decode [0.2, 0.6] maps to 0.6; alpha is never decoded.
        let image = try Image(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
            colorSpace: .deviceGray, alphaInfo: .none, decode: [0.2, 0.6], data: [255]
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(approx(color.red, 0.6, tol: 0.01))
    }

    @Test func eightBitDecodeIsUnchanged() throws {
        // Regression: the generic reader reproduces the original 8-bit RGBA decode.
        let image = try Image(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            colorSpace: .deviceRGB, alphaInfo: .last, data: [255, 128, 0, 255]
        )
        let color = image.pixelColor(x: 0, y: 0)
        #expect(approx(color.red, 1.0, tol: 0.01))
        #expect(approx(color.green, 128.0 / 255.0, tol: 0.01))
        #expect(approx(color.blue, 0.0, tol: 0.01))
        #expect(approx(color.alpha, 1.0, tol: 0.01))
    }
}
