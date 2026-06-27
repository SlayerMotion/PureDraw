//
//  PNGFilterTests.swift
//  PureDraw
//
//  Covers PNGEncoder's adaptive scanline filtering: that filtered output still round-trips exactly
//  through the decoder, that it dramatically shrinks correlated images, and that the encoder really
//  chooses among the five filter types rather than always emitting filter 0.
//

@testable import Core
import Renderers
import Testing

struct PNGFilterTests {
    private func image(_ width: Int, _ height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> Image {
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
        return try Image(width: width, height: height, alphaInfo: .last, data: rgba)
    }

    @Test func filteredPNGRoundTripsThroughDecoder() throws {
        // A mix of content that favours different filters: a 2D gradient (Paeth/Up), horizontal
        // bands (Up), a left-to-right ramp (Sub), and noise (None).
        let cases: [(String, (Int, Int) -> (UInt8, UInt8, UInt8))] = [
            ("gradient", { x, y in (UInt8(x % 256), UInt8(y % 256), UInt8((x + y) % 256)) }),
            ("bands", { _, y in (UInt8(y % 256), 0, UInt8((y * 3) % 256)) }),
            ("ramp", { x, _ in (UInt8(x % 256), 128, UInt8((255 - x) % 256)) }),
            ("noise", { x, y in (UInt8((x * 31 + y * 17) % 256), UInt8((x * 7) % 256), UInt8((y * 13) % 256)) }),
        ]
        for (name, pixel) in cases {
            let source = try image(73, 49, pixel) // odd dimensions to exercise edges
            let png = PNGEncoder.encode(source)
            let decoded = try ImageDecoder.decode(png)
            #expect(decoded.width == 73 && decoded.height == 49, "\(name)")
            #expect(decoded.data == source.data, "\(name) must round-trip exactly")
        }
    }

    @Test func adaptiveFilteringShrinksCorrelatedImages() throws {
        let (w, h) = (256, 256)
        let gradient = try image(w, h) { x, y in (UInt8(x), UInt8(y), UInt8((x + y) / 2)) }
        let png = PNGEncoder.encode(gradient)
        // A smooth gradient becomes near-zero residuals after filtering; only filtering can drive the
        // file this far below the raw RGBA size (filter 0 alone leaves it near-incompressible).
        #expect(png.count < w * h * 4 / 50)
    }

    @Test func selectsMoreThanOneFilterType() throws {
        // A gradient picks Up/Paeth on most rows but None on row 0 (no row above helps), so the
        // per-scanline filter bytes must include at least two distinct values.
        let source = try image(64, 64) { x, y in (UInt8(x), UInt8(y), UInt8((x + y) / 2)) }
        let png = PNGEncoder.encode(source)
        let raw = try #require(Inflate.zlib(idat(of: png)))

        let rowBytes = 64 * 4
        var filterTypes: Set<UInt8> = []
        var offset = 0
        while offset < raw.count {
            filterTypes.insert(raw[offset])
            offset += rowBytes + 1 // one filter byte then the row
        }
        #expect(filterTypes.count >= 2)
        #expect(filterTypes.contains { $0 != 0 }) // at least one real (non-None) filter was chosen
    }

    /// Concatenates the IDAT chunk bodies of a PNG (the zlib stream).
    private func idat(of png: [UInt8]) -> [UInt8] {
        var data: [UInt8] = []
        var pos = 8 // after the signature
        while pos + 8 <= png.count {
            let length = Int(png[pos]) << 24 | Int(png[pos + 1]) << 16 | Int(png[pos + 2]) << 8 | Int(png[pos + 3])
            let type = String(decoding: png[pos + 4 ..< pos + 8], as: UTF8.self)
            let bodyStart = pos + 8
            if type == "IDAT" { data.append(contentsOf: png[bodyStart ..< bodyStart + length]) }
            pos = bodyStart + length + 4 // skip body and CRC
        }
        return data
    }
}
