//
//  PNGBitDepthTests.swift
//  PureDraw
//
//  Hermetic, dependency-free coverage of the decoder's sub-byte bit depths. Each test hand-builds a
//  minimal grayscale PNG with known packed pixels (filter 0, zlib via Deflate) and asserts the exact
//  decoded RGBA, pinning the MSB-first bit unpacking and the sub-byte-to-8-bit scaling. CoreGraphics
//  cross-checks of every depth and interlacing live in RenderersTests/PNGVariantOracleTests.
//

@testable import Core
import Testing

struct PNGBitDepthTests {
    @Test func decodes1BitGrayscale() throws {
        // 4x2, 1 bit/pixel, MSB-first. Row 0 pixels [0,1,0,1] -> 0b0101_0000 = 0x50; row 1 [1,0,1,0]
        // -> 0xA0. Each row is a filter byte (0) then the packed byte.
        let png = grayscalePNG(width: 4, height: 2, bitDepth: 1, scanlines: [0x00, 0x50, 0x00, 0xA0])
        let image = try ImageDecoder.decode(png)
        #expect(image.width == 4 && image.height == 2)
        let black: [UInt8] = [0, 0, 0, 255]
        let white: [UInt8] = [255, 255, 255, 255]
        #expect(image.data == black + white + black + white + white + black + white + black)
    }

    @Test func decodes4BitGrayscale() throws {
        // 4x1, 4 bits/pixel. Pixels [0, 5, 10, 15] pack to bytes 0x05, 0xAF (after the filter byte).
        let png = grayscalePNG(width: 4, height: 1, bitDepth: 4, scanlines: [0x00, 0x05, 0xAF])
        let image = try ImageDecoder.decode(png)
        #expect(image.width == 4 && image.height == 1)
        func gray(_ value: UInt8) -> [UInt8] {
            [value, value, value, 255]
        }
        // 4-bit scaling is value * 255 / 15: 0, 85, 170, 255.
        #expect(image.data == gray(0) + gray(85) + gray(170) + gray(255))
    }

    @Test func decodes2BitGrayscale() throws {
        // 4x1, 2 bits/pixel. Pixels [0,1,2,3] -> 0b00_01_10_11 = 0x1B (after the filter byte).
        let png = grayscalePNG(width: 4, height: 1, bitDepth: 2, scanlines: [0x00, 0x1B])
        let image = try ImageDecoder.decode(png)
        func gray(_ value: UInt8) -> [UInt8] {
            [value, value, value, 255]
        }
        // 2-bit scaling is value * 255 / 3: 0, 85, 170, 255.
        #expect(image.data == gray(0) + gray(85) + gray(170) + gray(255))
    }

    @Test func rejectsOversizedDimensionsWithoutTrapping() {
        // An IHDR declaring ~268M x ~268M pixels (a width*height overflow and OOM risk) must throw a
        // catchable error before any image-sized allocation, never trap.
        var ihdr: [UInt8] = []
        appendBigEndian(0x1000_0000, to: &ihdr) // width
        appendBigEndian(0x1000_0000, to: &ihdr) // height
        ihdr += [8, 0, 0, 0, 0] // 8-bit grayscale, deflate, filter 0, no interlace
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += chunk("IHDR", ihdr)
        png += chunk("IDAT", zlib([0x00]))
        png += chunk("IEND", [])
        #expect(throws: ImageDecoder.Error.self) {
            try ImageDecoder.decode(png)
        }
    }

    @Test func acceptsLongThinDimensionsWithinPixelBudget() {
        // 100000 x 100 (10 megapixels) is wider than a 16-bit field but well under the pixel budget,
        // and CoreGraphics decodes it. The dimension guard must accept the header (decoding then fails
        // on the deliberately absent pixel data, a different and later error, never "too large").
        var ihdr: [UInt8] = []
        appendBigEndian(100_000, to: &ihdr)
        appendBigEndian(100, to: &ihdr)
        ihdr += [8, 0, 0, 0, 0]
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += chunk("IHDR", ihdr)
        png += chunk("IDAT", zlib([0x00]))
        png += chunk("IEND", [])
        do {
            _ = try ImageDecoder.decode(png)
            Issue.record("expected a decode error for the missing pixel data")
        } catch let ImageDecoder.Error.unsupportedFormat(message) where message.contains("too large") {
            Issue.record("a long/thin image within the pixel budget was wrongly rejected as too large")
        } catch {
            // Any other error (here, a truncated IDAT) is the expected outcome: the dimensions passed.
        }
    }

    // MARK: - Minimal PNG builder

    private func grayscalePNG(width: Int, height: Int, bitDepth: Int, scanlines: [UInt8]) -> [UInt8] {
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        var ihdr: [UInt8] = []
        appendBigEndian(UInt32(width), to: &ihdr)
        appendBigEndian(UInt32(height), to: &ihdr)
        ihdr += [UInt8(bitDepth), 0, 0, 0, 0] // grayscale, deflate, filter method 0, no interlace
        png += chunk("IHDR", ihdr)
        png += chunk("IDAT", zlib(scanlines))
        png += chunk("IEND", [])
        return png
    }

    private func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let typeBytes = Array(type.utf8)
        var out: [UInt8] = []
        appendBigEndian(UInt32(data.count), to: &out)
        out += typeBytes + data
        appendBigEndian(crc32(typeBytes + data), to: &out)
        return out
    }

    /// Wraps raw bytes in a zlib stream (DEFLATE-compressed via `Deflate`, with an adler32 trailer).
    private func zlib(_ raw: [UInt8]) -> [UInt8] {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        var out: [UInt8] = [0x78, 0x01]
        out += Deflate.compressed(raw)
        appendBigEndian((b << 16) | a, to: &out)
        return out
    }

    private func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                crc = (crc & 1) == 1 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private func appendBigEndian(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes += [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
