#if canImport(ImageIO) // the ImageIO JPEG codec is the Apple-only oracle; these cross-checks skip elsewhere
//
    //  JPEGDecoderOracleTests.swift
    //  PureDraw
//
    //  JPEGDecoder handles the baseline AC, YCbCr, and chroma-subsampling paths that the hermetic
    //  grayscale fixtures in CoreTests cannot reach. They are verified against ImageIO: a known
    //  image is encoded to a baseline JPEG once, then decoded BOTH by PureDraw and by CoreGraphics.
    //  Because both decoders see the identical quantized coefficients, the only differences are
    //  inverse-DCT rounding and chroma upsampling, so a small tolerance pins down correctness
    //  without depending on JPEG's lossiness.
//

    @testable import Core
    import CoreGraphics
    import Foundation
    import ImageIO
    import Testing

    struct JPEGDecoderOracleTests {
        /// A smooth RGB gradient. Slowly varying chroma keeps nearest-neighbor and "fancy" upsampling
        /// close, so the comparison isolates decoder correctness rather than upsampling policy.
        private func gradientRGBA(width: Int, height: Int) -> [UInt8] {
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
            return data
        }

        private func makeCGImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
            return CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: cs,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }

        private func encodeJPEG(_ image: CGImage, quality: CGFloat) -> [UInt8]? {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return [UInt8](out as Data)
        }

        /// Decodes JPEG bytes through CoreGraphics into a straight RGBA buffer (the reference).
        private func decodeWithCoreGraphics(_ jpeg: [UInt8], width: Int, height: Int) -> [UInt8]? {
            guard let source = CGImageSourceCreateWithData(Data(jpeg) as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = buffer.withUnsafeMutableBytes({ raw in
                CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )
            }) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return buffer
        }

        @Test(arguments: [1.0, 0.85])
        func matchesCoreGraphicsDecode(quality: Double) throws {
            let (w, h) = (48, 32)
            let original = gradientRGBA(width: w, height: h)
            let cgImage = try #require(makeCGImage(rgba: original, width: w, height: h))
            let jpeg = try #require(encodeJPEG(cgImage, quality: CGFloat(quality)))

            // Sanity: it really is a baseline JPEG our decoder is meant to handle.
            #expect(jpeg.count >= 2 && jpeg[0] == 0xFF && jpeg[1] == 0xD8)

            let mine = try ImageDecoder.decode(jpeg)
            #expect(mine.width == w && mine.height == h)
            let reference = try #require(decodeWithCoreGraphics(jpeg, width: w, height: h))

            var maxDiff = 0
            var total = 0
            for pixel in 0 ..< w * h {
                let dst = pixel * 4
                for channel in 0 ..< 3 { // RGB; alpha is forced opaque on both sides
                    let diff = abs(Int(mine.data[dst + channel]) - Int(reference[dst + channel]))
                    maxDiff = max(maxDiff, diff)
                    total += diff
                }
            }
            let mean = Double(total) / Double(w * h * 3)
            #expect(maxDiff <= 12, "max channel diff vs CoreGraphics was \(maxDiff)")
            #expect(mean < 2.0, "mean channel diff vs CoreGraphics was \(mean)")
        }

        @Test func decodesGrayscaleJPEGFromImageIO() throws {
            // A single-component (grayscale) JPEG produced by ImageIO must decode to opaque gray.
            let (w, h) = (24, 16)
            var gray = [UInt8](repeating: 0, count: w * h * 4)
            for y in 0 ..< h {
                for x in 0 ..< w {
                    let v = UInt8(255 * x / (w - 1))
                    let i = (y * w + x) * 4
                    gray[i] = v
                    gray[i + 1] = v
                    gray[i + 2] = v
                    gray[i + 3] = 255
                }
            }
            let cgImage = try #require(makeCGImage(rgba: gray, width: w, height: h))
            // Re-encode through a gray color space so ImageIO emits a 1-component JPEG.
            let grayCS = CGColorSpaceCreateDeviceGray()
            guard let grayCtx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: grayCS, bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            grayCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            let grayImage = try #require(grayCtx.makeImage())
            let jpeg = try #require(encodeJPEG(grayImage, quality: 0.95))

            let mine = try ImageDecoder.decode(jpeg)
            #expect(mine.width == w && mine.height == h)
            let reference = try #require(decodeWithCoreGraphics(jpeg, width: w, height: h))
            var maxDiff = 0
            for pixel in 0 ..< w * h {
                let dst = pixel * 4
                #expect(mine.data[dst] == mine.data[dst + 1] && mine.data[dst + 1] == mine.data[dst + 2])
                for channel in 0 ..< 3 {
                    maxDiff = max(maxDiff, abs(Int(mine.data[dst + channel]) - Int(reference[dst + channel])))
                }
            }
            #expect(maxDiff <= 12, "grayscale max diff vs CoreGraphics was \(maxDiff)")
        }
    }
#endif
