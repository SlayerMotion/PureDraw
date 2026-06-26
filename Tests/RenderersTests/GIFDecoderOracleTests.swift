#if canImport(ImageIO) // ImageIO is the Apple-only oracle; these cross-checks skip elsewhere
//
    //  GIFDecoderOracleTests.swift
    //  PureDraw
//
    //  GIF decoding is lossless given the palette, so PureDraw and CoreGraphics decoding the SAME GIF
    //  bytes must agree EXACTLY (no inverse-DCT or upsampling tolerance, unlike JPEG). These cross-check
    //  static and animated (first-frame) GIFs against ImageIO; interlacing and transparency, which
    //  ImageIO does not emit, are covered hermetically in CoreTests/GIFDecoderTests.
//

    @testable import Core
    import CoreGraphics
    import Foundation
    import ImageIO
    import Testing

    struct GIFDecoderOracleTests {
        private func makeCGImage(_ width: Int, _ height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage? {
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let (r, g, b) = pixel(x, y)
                    let i = (y * width + x) * 4
                    rgba[i] = r
                    rgba[i + 1] = g
                    rgba[i + 2] = b
                    rgba[i + 3] = 255
                }
            }
            guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
            return CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
        }

        private func encodeGIF(_ images: [CGImage]) -> [UInt8]? {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, "com.compuserve.gif" as CFString, images.count, nil) else { return nil }
            let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
            for image in images {
                CGImageDestinationAddImage(dest, image, props)
            }
            guard CGImageDestinationFinalize(dest) else { return nil }
            return [UInt8](out as Data)
        }

        /// Decodes GIF bytes through CoreGraphics into a straight RGBA buffer at `frame`.
        private func decodeWithCoreGraphics(_ gif: [UInt8], width: Int, height: Int, frame: Int = 0) -> [UInt8]? {
            guard let source = CGImageSourceCreateWithData(Data(gif) as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, frame, nil)
            else { return nil }
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            guard let ctx = buffer.withUnsafeMutableBytes({ raw in
                CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            }) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return buffer
        }

        /// Premultiplies straight RGBA to compare against CoreGraphics's premultiplied output (GIF alpha
        /// is 1-bit, so this only zeroes fully-transparent pixels).
        private func premultiplied(_ straight: [UInt8]) -> [UInt8] {
            var out = straight
            for p in stride(from: 0, to: out.count, by: 4) where out[p + 3] == 0 {
                out[p] = 0
                out[p + 1] = 0
                out[p + 2] = 0
            }
            return out
        }

        @Test func decodesStaticGIFExactlyLikeCoreGraphics() throws {
            let (w, h) = (64, 48)
            let image = try #require(makeCGImage(w, h) { x, y in
                (UInt8(255 * x / (w - 1)), UInt8(255 * y / (h - 1)), UInt8(255 * (x + y) / (w + h - 2)))
            })
            let gif = try #require(encodeGIF([image]))
            #expect(gif.prefix(3) == [0x47, 0x49, 0x46]) // "GIF"

            let mine = try ImageDecoder.decode(gif)
            #expect(mine.width == w && mine.height == h)
            let reference = try #require(decodeWithCoreGraphics(gif, width: w, height: h))
            // Lossless: PureDraw and CoreGraphics must agree exactly on every channel.
            #expect(premultiplied(mine.data) == reference)
        }

        @Test func decodesFirstFrameOfAnimatedGIF() throws {
            let (w, h) = (32, 24)
            let frame0 = try #require(makeCGImage(w, h) { x, _ in (UInt8(255 * x / (w - 1)), 0, 0) })
            let frame1 = try #require(makeCGImage(w, h) { _, y in (0, UInt8(255 * y / (h - 1)), 0) })
            let gif = try #require(encodeGIF([frame0, frame1]))

            let mine = try ImageDecoder.decode(gif)
            #expect(mine.width == w && mine.height == h)
            // PureDraw decodes the first frame; it must match CoreGraphics's frame 0 exactly.
            let reference = try #require(decodeWithCoreGraphics(gif, width: w, height: h, frame: 0))
            #expect(premultiplied(mine.data) == reference)
        }
    }
#endif
