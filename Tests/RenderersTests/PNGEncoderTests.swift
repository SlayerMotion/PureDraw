//
//  PNGEncoderTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

struct PNGEncoderTests {
    @Test func encodesValidPNGStructure() throws {
        let image = try Image(width: 2, height: 2, alphaInfo: .last, data: [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 128,
        ])
        let png = PNGEncoder.encode(image)

        // PNG signature.
        #expect(Array(png[0 ..< 8]) == [137, 80, 78, 71, 13, 10, 26, 10])
        // IHDR: 13-byte payload, then the type.
        #expect(Array(png[8 ..< 16]) == [0, 0, 0, 13, 73, 72, 68, 82])
        // 2x2 dimensions, big endian.
        #expect(Array(png[16 ..< 24]) == [0, 0, 0, 2, 0, 0, 0, 2])
        // 8-bit RGBA, deflate, filter 0, no interlace.
        #expect(Array(png[24 ..< 29]) == [8, 6, 0, 0, 0])
        // The file ends with IEND and its well-known CRC.
        #expect(Array(png.suffix(8)) == [73, 69, 78, 68, 0xAE, 0x42, 0x60, 0x82])
    }

    @Test func roundTripsThroughCoreGraphics() throws {
        #if canImport(CoreGraphics)
            let image = try Image(width: 2, height: 2, alphaInfo: .last, data: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255,
            ])
            let png = PNGEncoder.encode(image)

            let data = png.withUnsafeBufferPointer { CFDataCreate(nil, $0.baseAddress, $0.count) }
            guard let cfData = data,
                  let provider = CGDataProvider(data: cfData),
                  let decoded = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            else {
                Issue.record("CoreGraphics could not decode the encoded PNG")
                return
            }

            #expect(decoded.width == 2)
            #expect(decoded.height == 2)

            guard let cgContext = CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let buffer = { cgContext.draw(decoded, in: CGRect(x: 0, y: 0, width: 2, height: 2))
                return cgContext.data
            }()
            else {
                Issue.record("Failed to redraw the decoded PNG")
                return
            }

            let pixels = buffer.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = cgContext.bytesPerRow
            // Row 0: red, green. Row 1: blue, white.
            #expect(pixels[0] == 255 && pixels[1] == 0 && pixels[2] == 0 && pixels[3] == 255)
            #expect(pixels[4] == 0 && pixels[5] == 255 && pixels[6] == 0)
            #expect(pixels[bytesPerRow + 2] == 255 && pixels[bytesPerRow + 0] == 0)
            #expect(pixels[bytesPerRow + 4] == 255 && pixels[bytesPerRow + 5] == 255 && pixels[bytesPerRow + 6] == 255)
        #endif
    }
}
