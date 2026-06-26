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

        /// Encodes a progressive (multi-scan, SOF2) JPEG via ImageIO's JFIF progressive flag.
        private func encodeProgressiveJPEG(_ image: CGImage, quality: CGFloat) -> [UInt8]? {
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
            let properties: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality,
                kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFIsProgressive: true],
            ]
            CGImageDestinationAddImage(dest, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return [UInt8](out as Data)
        }

        /// A high-frequency *luminance* pattern (the three channels move together, so chroma stays
        /// near zero). This spreads luma energy across many AC coefficients, exercising the AC-first
        /// and AC-refinement scans, without stressing 4:2:0 chroma upsampling (a separate
        /// approximation that would otherwise dominate the comparison on high-frequency chroma).
        private func highFrequencyLumaRGBA(width: Int, height: Int) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let i = (y * width + x) * 4
                    let value = UInt8((x * 17 + y * 29) % 256)
                    data[i] = value
                    data[i + 1] = value
                    data[i + 2] = value
                    data[i + 3] = 255
                }
            }
            return data
        }

        /// A smooth diagonal color sweep: each channel ramps in a different direction, so chroma
        /// (Cb/Cr) varies strongly but continuously. At 4:2:0 this exercises chroma upsampling hard
        /// while staying free of the sharp discontinuities that would confound the comparison with
        /// the inverse-DCT divergence.
        private func chromaSweepRGBA(width: Int, height: Int) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let i = (y * width + x) * 4
                    data[i] = UInt8(255 * x / max(width - 1, 1))
                    data[i + 1] = UInt8(255 * (height - 1 - y) / max(height - 1, 1))
                    data[i + 2] = UInt8(255 * y / max(height - 1, 1))
                    data[i + 3] = 255
                }
            }
            return data
        }

        /// Strongly-varying chroma at 4:2:0 must match CoreGraphics closely, which requires centered
        /// "fancy" chroma upsampling (nearest-neighbour upsampling would diverge by tens of levels).
        @Test func upsamplesSubsampledChromaLikeCoreGraphics() throws {
            let (w, h) = (64, 48)
            let source = chromaSweepRGBA(width: w, height: h)
            let cgImage = try #require(makeCGImage(rgba: source, width: w, height: h))
            // Quality 0.9 keeps ImageIO on 4:2:0 subsampling for this size.
            let jpeg = try #require(encodeJPEG(cgImage, quality: 0.9))
            let mine = try ImageDecoder.decode(jpeg)
            let reference = try #require(decodeWithCoreGraphics(jpeg, width: w, height: h))
            var maxDiff = 0
            for pixel in 0 ..< w * h {
                let dst = pixel * 4
                for channel in 0 ..< 3 {
                    maxDiff = max(maxDiff, abs(Int(mine.data[dst + channel]) - Int(reference[dst + channel])))
                }
            }
            #expect(maxDiff <= 12, "subsampled-chroma max diff vs CoreGraphics was \(maxDiff)")
        }

        /// A 4:4:0 (h1v2, vertical-only chroma subsampling) JPEG, a layout ImageIO never emits but
        /// must decode. Generated offline with `cjpeg -sample 1x2` over a smooth color sweep. Matching
        /// CoreGraphics requires centered *vertical* chroma upsampling; nearest-neighbour would band.
        @Test func decodes440ChromaLikeCoreGraphics() throws {
            let base64 = """
            /9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMU
            FRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU
            FBQUFBQUFBT/wAARCAAwAEADARIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUF
            BAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVW
            V1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi
            4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAEC
            AxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVm
            Z2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq
            8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDrLTWOnzVxFpq/T5q/nKfC390/hrDZd5HqNpq/T5q4i01fp81cM+Fv7p9Xhsu8j1G01jp8
            1cRaav0+auCfC390+rwuXeR6jaax0+auItNX6fNXBPhb+6fWYbL/ACPULTV+nzVxFpq/T5q4Z8Lf3T6rDZf5HqNprHT5q4i01fp8
            1cE+Fv7p9Xhsu8j1G01jp81cRaav0+auGfC390+rw2XeR6jaav0+auItNX6fNXBPhb+6fV4bLvI+FLTV+nzVxFpq/T5q/wBJ58Lf
            3T+IMNl3keoWmr9PmriLTV+nzVwT4W/un1WGy7yPUbTV+nzVxFpq/T5q4Z8Lf3T6vC5d5HqNpq/T5q4i01fp81cE+Fv7p9Zhsu8j
            1G01fp81cRaav0+auGfC390+rw2XeR6jaav0+auItNX6fNXBPhb+6fV4bLvI9QtNX6fNXEWmr9Pmrgnwt/dPq8Nl3keo2mr9Pmri
            LTV+nzVwz4W/un1eGy7yPhS01fp81cRaav05r/SafC390/iDDZd5HqFpq/T5q4m01fpzXDPhb+6fVYbLvI9QtNX6fNXE2mr9Oa4J
            8Lf3T6zC5d5HqFpq/T5q4m01fpzXBPhb+6fV4bL/ACPULTV+nzVxFpq/TmuGfC390+rw2X+R6jaav0+auItNX6c1wT4W/un1eGy7
            yPUbTV+nzVxFpq/TmuGfC390+rw2XeR6haav0+auJtNX6c1wT4W/un1eGy7yP//Z
            """
            let data = try #require(Data(base64Encoded: base64, options: .ignoreUnknownCharacters))
            let jpeg = [UInt8](data)
            let (w, h) = (64, 48)
            let mine = try ImageDecoder.decode(jpeg)
            #expect(mine.width == w && mine.height == h)
            let reference = try #require(decodeWithCoreGraphics(jpeg, width: w, height: h))
            var maxDiff = 0
            for pixel in 0 ..< w * h {
                let dst = pixel * 4
                for channel in 0 ..< 3 {
                    maxDiff = max(maxDiff, abs(Int(mine.data[dst + channel]) - Int(reference[dst + channel])))
                }
            }
            #expect(maxDiff <= 12, "4:4:0 max diff vs CoreGraphics was \(maxDiff)")
        }

        /// True if the byte stream carries an SOF2 (progressive) frame header.
        private func isProgressive(_ jpeg: [UInt8]) -> Bool {
            var i = 0
            while i + 1 < jpeg.count {
                if jpeg[i] == 0xFF, jpeg[i + 1] == 0xC2 { return true }
                i += 1
            }
            return false
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

        /// Representative qualities that still produce the full multi-scan progressive structure
        /// (DC first/refine, AC first/refine). Very low qualities are excluded: they only surface
        /// the float-vs-integer inverse-DCT divergence from CoreGraphics on heavy quantization, which
        /// the baseline decoder shares and which is unrelated to progressive decoding.
        @Test(arguments: [0.75, 0.95])
        func decodesProgressiveJPEG(quality: Double) throws {
            let (w, h) = (48, 32)
            // Both a smooth gradient and a high-frequency luma pattern, so the scan set spans DC,
            // AC-first, and AC-refinement scans across several spectral bands.
            for source in [gradientRGBA(width: w, height: h), highFrequencyLumaRGBA(width: w, height: h)] {
                let cgImage = try #require(makeCGImage(rgba: source, width: w, height: h))
                let jpeg = try #require(encodeProgressiveJPEG(cgImage, quality: CGFloat(quality)))
                #expect(isProgressive(jpeg), "ImageIO did not emit a progressive frame")

                let mine = try ImageDecoder.decode(jpeg)
                #expect(mine.width == w && mine.height == h)
                let reference = try #require(decodeWithCoreGraphics(jpeg, width: w, height: h))

                // Both decoders see identical coefficients, so agreement is bounded by inverse-DCT
                // rounding regardless of content; this validates every progressive scan type.
                var maxDiff = 0
                for pixel in 0 ..< w * h {
                    let dst = pixel * 4
                    for channel in 0 ..< 3 {
                        maxDiff = max(maxDiff, abs(Int(mine.data[dst + channel]) - Int(reference[dst + channel])))
                    }
                }
                #expect(maxDiff <= 10, "progressive q\(quality): max diff vs CoreGraphics was \(maxDiff)")
            }
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

        /// Builds a 1-component (DeviceGray) CGImage from a horizontal gray ramp.
        private func makeGrayCGImage(width: Int, height: Int) -> CGImage? {
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let v = UInt8(255 * x / max(width - 1, 1))
                    let i = (y * width + x) * 4
                    rgba[i] = v
                    rgba[i + 1] = v
                    rgba[i + 2] = v
                    rgba[i + 3] = 255
                }
            }
            guard let rgb = makeCGImage(rgba: rgba, width: width, height: height),
                  let ctx = CGContext(
                      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return nil }
            ctx.draw(rgb, in: CGRect(x: 0, y: 0, width: width, height: height))
            return ctx.makeImage()
        }

        /// A single-component progressive JPEG exercises the non-interleaved DC scan path (a DC scan
        /// with one component is NOT interleaved over the MCU grid). Decode must match CoreGraphics.
        @Test func decodesGrayscaleProgressiveJPEG() throws {
            let (w, h) = (32, 24)
            let grayImage = try #require(makeGrayCGImage(width: w, height: h))
            let jpeg = try #require(encodeProgressiveJPEG(grayImage, quality: 0.85))
            #expect(isProgressive(jpeg), "ImageIO did not emit a progressive frame")

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
            #expect(maxDiff <= 10, "grayscale progressive max diff vs CoreGraphics was \(maxDiff)")
        }

        @Test func decodesGrayscaleJPEGFromImageIO() throws {
            // A single-component (grayscale) JPEG produced by ImageIO must decode to opaque gray.
            let (w, h) = (24, 16)
            let grayImage = try #require(makeGrayCGImage(width: w, height: h))
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
