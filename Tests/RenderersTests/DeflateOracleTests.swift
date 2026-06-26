#if canImport(Compression) && canImport(ImageIO) // Apple-only oracles; skip elsewhere
//
    //  DeflateOracleTests.swift
    //  PureDraw
//
    //  Cross-checks the DEFLATE compressor against Apple's own implementations, so correctness does not
    //  rest on PureDraw's `Inflate` alone: the system zlib (Compression framework) must decode our raw
    //  DEFLATE byte-for-byte, and ImageIO must decode a PNG whose IDAT we now actually compress.
//

    import Compression
    @testable import Core
    import CoreGraphics
    import Foundation
    import ImageIO
    import Renderers
    import Testing

    struct DeflateOracleTests {
        /// Decodes raw DEFLATE with the system zlib (COMPRESSION_ZLIB is raw RFC 1951, no zlib wrapper).
        private func systemInflate(_ deflated: [UInt8], expectedSize: Int) -> [UInt8]? {
            guard expectedSize > 0, !deflated.isEmpty else { return nil }
            var out = [UInt8](repeating: 0, count: expectedSize)
            let written = out.withUnsafeMutableBufferPointer { dst in
                deflated.withUnsafeBufferPointer { src in
                    guard let destination = dst.baseAddress, let source = src.baseAddress else { return 0 }
                    return compression_decode_buffer(destination, dst.count, source, src.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard written == expectedSize else { return nil }
            return out
        }

        @Test func systemZlibDecodesOurDeflate() {
            let inputs: [[UInt8]] = [
                [UInt8](repeating: 0x42, count: 50000), // long run
                (0 ..< 20000).map { UInt8($0 % 7) }, // short repeating pattern
                Array("the quick brown fox jumps over the lazy dog ".utf8.map { $0 }) + Array(repeating: 0x20, count: 200),
                (0 ..< 4096).map { UInt8(($0 &* 2_654_435_761) >> 24 & 0xFF) }, // scrambled, near-incompressible
            ]
            for data in inputs {
                let deflated = Deflate.compressed(data)
                let restored = systemInflate(deflated, expectedSize: data.count)
                #expect(restored == data) // Apple's zlib agrees with our compressor
            }
        }

        @Test func imageIODecodesCompressedPNG() throws {
            let (w, h) = (96, 72)
            var rgba = [UInt8](repeating: 0, count: w * h * 4)
            for y in 0 ..< h {
                for x in 0 ..< w {
                    let i = (y * w + x) * 4
                    rgba[i] = UInt8(x * 255 / (w - 1))
                    rgba[i + 1] = UInt8(y * 255 / (h - 1))
                    rgba[i + 2] = 128
                    rgba[i + 3] = 255
                }
            }
            let image = try Image(width: w, height: h, alphaInfo: .last, data: rgba)
            let png = PNGEncoder.encode(image)

            // The IDAT is genuinely compressed now: a smooth gradient must beat the uncompressed size.
            let uncompressed = h * (1 + w * 4)
            #expect(png.count < uncompressed)

            // ImageIO (a real PNG decoder using real zlib) must decode our compressed PNG back exactly.
            let source = try #require(CGImageSourceCreateWithData(Data(png) as CFData, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(decoded.width == w && decoded.height == h)
            var out = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = try #require(out.withUnsafeMutableBytes { raw in
                CGContext(
                    data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            })
            ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: w, height: h))
            // Opaque gradient: premultiplied == straight, so it must match the source pixels exactly.
            #expect(out == rgba)
        }
    }
#endif
