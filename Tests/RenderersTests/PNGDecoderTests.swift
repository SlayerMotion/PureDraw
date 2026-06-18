//
//  PNGDecoderTests.swift
//  PureDraw
//
//  ImageDecoder turns encoded bytes back into a raw-RGBA Image (PureDraw #103). Verified three
//  ways: a full round-trip through PNGEncoder (PNG chunks + stored inflate + filter-none +
//  RGBA assembly), the raw DEFLATE inflate against the system compressor (the Huffman + LZ77
//  back-reference paths PNGEncoder's stored blocks do not exercise), and a hand-built
//  Sub-filtered PNG (the scanline-filter reconstruction).
//

import Compression
@testable import Core
import Foundation
import Renderers
import Testing

struct PNGDecoderTests {
    /// A small RGBA image with varied, non-uniform pixels so filters and channels all matter.
    private func sampleRGBA(width: Int, height: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = (y * width + x) * 4
                data[i] = UInt8((x * 23 + y * 7) & 0xFF)
                data[i + 1] = UInt8((x * 5 + y * 31) & 0xFF)
                data[i + 2] = UInt8((x * 13 + y * 17 + 40) & 0xFF)
                data[i + 3] = UInt8((x + y) % 2 == 0 ? 255 : 128)
            }
        }
        return data
    }

    @Test func decodesPNGEncoderRoundTrip() throws {
        let (w, h) = (12, 9)
        let pixels = sampleRGBA(width: w, height: h)
        let image = try Image(width: w, height: h, alphaInfo: .last, data: pixels)
        let png = PNGEncoder.encode(image)
        let decoded = try ImageDecoder.decode(png)
        #expect(decoded.width == w && decoded.height == h)
        #expect(decoded.data == pixels, "round-tripped RGBA pixels must be identical")
    }

    /// Raw DEFLATE via the system compressor, so the test exercises the Huffman + back-reference
    /// inflate paths (PNGEncoder only emits stored blocks).
    private func systemRawDeflate(_ data: [UInt8]) -> [UInt8] {
        let capacity = data.count + 128
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { dst.deallocate() }
        let n = data.withUnsafeBufferPointer { src -> Int in
            guard let base = src.baseAddress else { return 0 }
            return compression_encode_buffer(dst, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return Array(UnsafeBufferPointer(start: dst, count: n))
    }

    @Test func inflateMatchesSystemDeflate() {
        // Repetitive + varied data forces literals, matches (back-references), and a non-trivial
        // Huffman tree.
        var data: [UInt8] = []
        for i in 0 ..< 4000 {
            data.append(UInt8((i * 7) % 11 + (i % 97 == 0 ? 200 : 0)))
        }
        data.append(contentsOf: Array("the quick brown fox ".utf8).flatMap { _ in Array("the quick brown fox ".utf8) })
        let compressed = systemRawDeflate(data)
        #expect(!compressed.isEmpty)
        let inflated = Inflate.deflate(compressed)
        #expect(inflated == data, "inflate must reproduce the system-compressed data exactly")
    }

    @Test func zlibWrapperRoundTrips() {
        let data = Array("PureDraw zlib wrapper: header, deflate body, adler32 trailer.".utf8)
        var stream: [UInt8] = [0x78, 0x01]
        stream.append(contentsOf: systemRawDeflate(data))
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let adler = b << 16 | a
        stream.append(contentsOf: [UInt8(adler >> 24 & 0xFF), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)])
        #expect(Inflate.zlib(stream) == data, "zlib unwrap + inflate + adler check must round-trip")
    }

    @Test func decodesSubFilteredPNG() throws {
        // Build a PNG whose scanlines use the Sub filter (type 1) with a stored IDAT, to verify
        // the decoder's filter reconstruction independently of compression. The decoder ignores
        // chunk CRCs, so zero CRCs are fine here.
        let (w, h) = (6, 4)
        let pixels = sampleRGBA(width: w, height: h)
        let bpp = 4, rowBytes = w * bpp
        var rawScanlines: [UInt8] = []
        for y in 0 ..< h {
            rawScanlines.append(1) // Sub filter
            for i in 0 ..< rowBytes {
                let cur = Int(pixels[y * rowBytes + i])
                let left = i >= bpp ? Int(pixels[y * rowBytes + i - bpp]) : 0
                rawScanlines.append(UInt8((cur - left) & 0xFF))
            }
        }
        var png = pngSignature
        var ihdr = beBytes(w) + beBytes(h)
        ihdr += [8, 6, 0, 0, 0] // 8-bit RGBA, no interlace
        appendChunk("IHDR", ihdr, to: &png)
        appendChunk("IDAT", zlibStored(rawScanlines), to: &png)
        appendChunk("IEND", [], to: &png)

        let decoded = try ImageDecoder.decode(png)
        #expect(decoded.data == pixels, "Sub-filtered scanlines must reconstruct the original pixels")
    }

    @Test func rejectsJPEGAndDecodesDataURI() throws {
        #expect(throws: ImageDecoder.Error.self) { _ = try ImageDecoder.decode([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]) }

        let image = try Image(width: 3, height: 2, alphaInfo: .last, data: sampleRGBA(width: 3, height: 2))
        let png = PNGEncoder.encode(image)
        let uri = "data:image/png;base64," + Data(png).base64EncodedString()
        let decoded = try ImageDecoder.decode(dataURI: uri)
        #expect(decoded.width == 3 && decoded.height == 2)
        #expect(decoded.data == image.data, "data URI decode must match the source pixels")
    }

    // MARK: - Minimal PNG assembly helpers (CRC ignored by the decoder)

    private let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    private func beBytes(_ v: Int) -> [UInt8] {
        [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }

    private func appendChunk(_ type: String, _ data: [UInt8], to png: inout [UInt8]) {
        png += beBytes(data.count)
        png += Array(type.utf8)
        png += data
        png += [0, 0, 0, 0] // CRC placeholder; the decoder does not check it
    }

    private func zlibStored(_ raw: [UInt8]) -> [UInt8] {
        var stream: [UInt8] = [0x78, 0x01]
        let len = raw.count
        stream.append(1) // final stored block
        stream.append(contentsOf: [UInt8(len & 0xFF), UInt8(len >> 8 & 0xFF), UInt8(~len & 0xFF), UInt8(~len >> 8 & 0xFF)])
        stream += raw
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let adler = b << 16 | a
        stream.append(contentsOf: [UInt8(adler >> 24 & 0xFF), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)])
        return stream
    }
}
