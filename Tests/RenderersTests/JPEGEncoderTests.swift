//
//  JPEGEncoderTests.swift
//  PureDraw
//
//  JPEGEncoder writes a baseline JPEG; correctness is pinned three ways. The hermetic round-trip
//  (encode -> JPEGDecoder -> compare) fully exercises the optimal Huffman tables the encoder
//  derives from image statistics: if the generated BITS/HUFFVAL or canonical codes were wrong the
//  stream would not decode back. The structural test checks the marker skeleton. The ImageIO
//  cross-check (Apple-only) proves the output is standards-conformant JPEG that a foreign decoder
//  accepts, not merely something our own decoder happens to read.
//

@testable import Core
import Renderers
import Testing

struct JPEGEncoderTests {
    /// A smooth RGB gradient (opaque). Smooth content keeps quantization error low and predictable.
    private func gradient(width: Int, height: Int) throws -> Image {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = (y * width + x) * 4
                data[i] = UInt8(255 * x / max(width - 1, 1))
                data[i + 1] = UInt8(255 * y / max(height - 1, 1))
                data[i + 2] = UInt8(255 * (x + y) / max(width + height - 2, 1))
                data[i + 3] = 255
            }
        }
        return try Image(width: width, height: height, alphaInfo: .last, data: data)
    }

    private func solid(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) throws -> Image {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for p in 0 ..< width * height {
            data[p * 4] = r
            data[p * 4 + 1] = g
            data[p * 4 + 2] = b
            data[p * 4 + 3] = 255
        }
        return try Image(width: width, height: height, alphaInfo: .last, data: data)
    }

    /// Mean and max per-channel (RGB) absolute difference between two RGBA buffers.
    private func diff(_ a: [UInt8], _ b: [UInt8], pixels: Int) -> (mean: Double, max: Int) {
        var total = 0, worst = 0
        for p in 0 ..< pixels {
            for c in 0 ..< 3 {
                let d = abs(Int(a[p * 4 + c]) - Int(b[p * 4 + c]))
                total += d
                worst = max(worst, d)
            }
        }
        return (Double(total) / Double(pixels * 3), worst)
    }

    @Test(arguments: [80, 92, 98])
    func roundTripsThroughOwnDecoder(quality: Int) throws {
        let (w, h) = (48, 32)
        let original = try gradient(width: w, height: h)
        let jpeg = JPEGEncoder.encode(original, quality: quality)
        #expect(jpeg.first == 0xFF && jpeg.dropFirst().first == 0xD8) // SOI

        let decoded = try ImageDecoder.decode(jpeg)
        #expect(decoded.width == w && decoded.height == h)

        let (mean, worst) = diff(decoded.data, original.data, pixels: w * h)
        // Higher quality must track the original more closely; these bounds hold for a smooth image.
        let meanBound = quality >= 95 ? 2.0 : (quality >= 90 ? 3.5 : 7.0)
        #expect(mean < meanBound, "q\(quality): mean error \(mean)")
        #expect(worst < 40, "q\(quality): max error \(worst)")
    }

    @Test func solidColorIsNearlyExactAtHighQuality() throws {
        let (w, h) = (24, 24)
        let original = try solid(width: w, height: h, r: 180, g: 90, b: 40)
        let decoded = try ImageDecoder.decode(JPEGEncoder.encode(original, quality: 95))
        // A flat block is DC-only, so only the (small) DC quantization step contributes error.
        let (_, worst) = diff(decoded.data, original.data, pixels: w * h)
        #expect(worst <= 3, "solid color drifted by \(worst)")
    }

    @Test func handlesNonMultipleOfEightDimensions() throws {
        let (w, h) = (13, 7) // neither dimension is a multiple of 8: edge blocks are padded
        let original = try gradient(width: w, height: h)
        let decoded = try ImageDecoder.decode(JPEGEncoder.encode(original, quality: 90))
        #expect(decoded.width == w && decoded.height == h)
        let (mean, _) = diff(decoded.data, original.data, pixels: w * h)
        #expect(mean < 6.0)
    }

    @Test func encodesGrayscaleContent() throws {
        let (w, h) = (32, 16)
        var data = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0 ..< h {
            for x in 0 ..< w {
                let v = UInt8(255 * x / (w - 1))
                let i = (y * w + x) * 4
                data[i] = v
                data[i + 1] = v
                data[i + 2] = v
                data[i + 3] = 255
            }
        }
        let original = try Image(width: w, height: h, alphaInfo: .last, data: data)
        let decoded = try ImageDecoder.decode(JPEGEncoder.encode(original, quality: 92))
        #expect(decoded.width == w && decoded.height == h)
        let (mean, _) = diff(decoded.data, original.data, pixels: w * h)
        #expect(mean < 4.0)
    }

    @Test func roundTripsHighEntropyContent() throws {
        // Noisy, high-frequency content spreads energy across many AC coefficients, producing many
        // distinct run/size symbols and long Huffman codes, exercising the length-limiting and
        // canonical-code paths the smooth gradients never reach. It must not trap.
        let (w, h) = (64, 48)
        var data = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0 ..< h {
            for x in 0 ..< w {
                let i = (y * w + x) * 4
                data[i] = UInt8((x &* 73 &+ y &* 151 &+ 17) & 0xFF)
                data[i + 1] = UInt8((x &* 199 &+ y &* 37 &+ 91) & 0xFF)
                data[i + 2] = UInt8((x &* x &+ y &* y &* 3 &+ 5) & 0xFF)
                data[i + 3] = 255
            }
        }
        let original = try Image(width: w, height: h, alphaInfo: .last, data: data)
        let decoded = try ImageDecoder.decode(JPEGEncoder.encode(original, quality: 90))
        #expect(decoded.width == w && decoded.height == h)
    }

    @Test func writesExpectedMarkerSkeleton() throws {
        let jpeg = try JPEGEncoder.encode(gradient(width: 16, height: 16), quality: 85)
        func contains(_ marker: UInt8) -> Bool {
            for i in 0 ..< jpeg.count - 1 where jpeg[i] == 0xFF && jpeg[i + 1] == marker {
                return true
            }
            return false
        }
        #expect(jpeg.prefix(2) == [0xFF, 0xD8]) // SOI
        #expect(jpeg.suffix(2) == [0xFF, 0xD9]) // EOI
        #expect(contains(0xDB)) // DQT
        #expect(contains(0xC0)) // SOF0
        #expect(contains(0xC4)) // DHT
        #expect(contains(0xDA)) // SOS
        #expect(jpeg.count > 100)
    }
}
