#if canImport(ImageIO) // proves PureDraw's encoder output is standard JPEG a foreign decoder reads
//
    //  JPEGEncoderOracleTests.swift
    //  PureDraw
//
    //  The hermetic round-trip proves the encoder and our own decoder agree. This proves the stronger
    //  property the fidelity goal needs: a JPEG written by PureDraw is conformant enough that Apple's
    //  ImageIO decodes it back to the original image (within JPEG's lossy tolerance). If the markers,
    //  quantization tables, or optimally-generated Huffman tables were malformed, CGImageSource would
    //  fail or produce garbage.
//

    @testable import Core
    import CoreGraphics
    import Foundation
    import ImageIO
    import Renderers
    import Testing

    struct JPEGEncoderOracleTests {
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

        private func decodeWithCoreGraphics(_ jpeg: [UInt8], width: Int, height: Int) -> [UInt8]? {
            guard let source = CGImageSourceCreateWithData(Data(jpeg) as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            guard let ctx = buffer.withUnsafeMutableBytes({ raw in
                CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )
            }) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return buffer
        }

        @Test(arguments: [75, 90, 98])
        func imageIODecodesOurOutput(quality: Int) throws {
            let (w, h) = (40, 24)
            let original = try gradient(width: w, height: h)
            let jpeg = JPEGEncoder.encode(original, quality: quality)

            // ImageIO must recognize it as JPEG.
            let source = try #require(CGImageSourceCreateWithData(Data(jpeg) as CFData, nil))
            #expect((CGImageSourceGetType(source) as String?) == "public.jpeg")

            let reference = try #require(decodeWithCoreGraphics(jpeg, width: w, height: h))
            var total = 0, worst = 0
            for p in 0 ..< w * h {
                for c in 0 ..< 3 {
                    let d = abs(Int(reference[p * 4 + c]) - Int(original.data[p * 4 + c]))
                    total += d
                    worst = max(worst, d)
                }
            }
            let mean = Double(total) / Double(w * h * 3)
            // Total codec error (our quantization + ImageIO's IDCT) against the original.
            let meanBound = quality >= 95 ? 3.0 : (quality >= 85 ? 5.0 : 9.0)
            #expect(mean < meanBound, "q\(quality): ImageIO-decoded mean error \(mean)")
            #expect(worst < 60, "q\(quality): ImageIO-decoded max error \(worst)")
        }

        /// Our own decoder and ImageIO should agree closely on our encoder's output (both see identical
        /// coefficients; only IDCT rounding differs).
        @Test func ownDecoderAgreesWithImageIO() throws {
            let (w, h) = (40, 24)
            let jpeg = try JPEGEncoder.encode(gradient(width: w, height: h), quality: 90)
            let mine = try ImageDecoder.decode(jpeg)
            let theirs = try #require(decodeWithCoreGraphics(jpeg, width: w, height: h))
            var worst = 0
            for p in 0 ..< w * h {
                for c in 0 ..< 3 {
                    worst = max(worst, abs(Int(mine.data[p * 4 + c]) - Int(theirs[p * 4 + c])))
                }
            }
            #expect(worst <= 4, "our decoder vs ImageIO on our output diverged by \(worst)")
        }
    }
#endif
