//
//  GIFDecoderTests.swift
//  PureDraw
//
//  Hermetic, dependency-free coverage of the GIF decoder. A tiny hand-checked GIF (4x2, a global
//  color table of red/green/blue/white, LZW-compressed) pins the full pipeline: header and screen
//  descriptor parsing, the global color table, the graphic-control extension, the image descriptor,
//  LZW decompression, and palette mapping. The lossy-free correctness against CoreGraphics for
//  interlacing, transparency, and animation lives in RenderersTests/GIFDecoderOracleTests.
//

@testable import Core
import Testing

struct GIFDecoderTests {
    /// A 51-byte GIF89a, 4x2, columns red, green, blue, white (both rows identical). Produced by a
    /// reference encoder; the bytes are fixed so the expected pixels are exact.
    private let tinyGIF: [UInt8] = [
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x04, 0x00, 0x02, 0x00, 0xF1, 0x03, 0x00,
        0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        0x21, 0xF9, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x2C, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x02, 0x00, 0x00,
        0x02, 0x04, 0x44, 0x34, 0x86, 0x05, 0x00, 0x3B,
    ]

    @Test func decodesTinyPalettedGIF() throws {
        let image = try ImageDecoder.decode(tinyGIF)
        #expect(image.width == 4 && image.height == 2)
        #expect(image.alphaInfo == .last)

        let red: [UInt8] = [255, 0, 0, 255]
        let green: [UInt8] = [0, 255, 0, 255]
        let blue: [UInt8] = [0, 0, 255, 255]
        let white: [UInt8] = [255, 255, 255, 255]
        let expectedRow = red + green + blue + white
        let expected = expectedRow + expectedRow // two identical rows
        #expect(image.data == expected)
    }

    /// A 2x8 interlaced GIF (interlace bit set), one distinct color per row, produced offline by
    /// `magick ... -interlace Line`. Decoding must restore the four interlace passes to row order.
    @Test func decodesInterlacedGIF() throws {
        let bytes: [UInt8] = [
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x02, 0x00, 0x08, 0x00, 0xF2, 0x07, 0x00,
            0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0xFF, 0x00, 0x00,
            0x00, 0xFF, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0x21, 0xF9, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x2C, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x08, 0x00, 0x40,
            0x03, 0x0B, 0x18, 0x51, 0x45, 0x04, 0x40, 0x88, 0x31, 0x8C, 0x39, 0x27, 0x01, 0x00, 0x3B,
        ]
        let image = try ImageDecoder.decode(bytes)
        #expect(image.width == 2 && image.height == 8)
        let rows: [(UInt8, UInt8, UInt8)] = [
            (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0),
            (255, 0, 255), (0, 255, 255), (0, 0, 0), (255, 255, 255),
        ]
        var expected: [UInt8] = []
        for color in rows {
            expected += [color.0, color.1, color.2, 255, color.0, color.1, color.2, 255]
        }
        #expect(image.data == expected)
    }

    /// A 4x2 GIF whose color index 0 is the transparent color; those pixels must decode to a fully
    /// transparent (alpha 0) sample, the rest opaque.
    @Test func decodesTransparentGIF() throws {
        let bytes: [UInt8] = [
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x04, 0x00, 0x02, 0x00, 0xF1, 0x00, 0x00,
            0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF,
            0x21, 0xF9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00,
            0x2C, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x02, 0x00, 0x00,
            0x02, 0x04, 0x44, 0x34, 0x86, 0x05, 0x00, 0x3B,
        ]
        let image = try ImageDecoder.decode(bytes)
        #expect(image.width == 4 && image.height == 2)
        let row: [UInt8] = [0, 0, 0, 0, 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255]
        #expect(image.data == row + row)
    }

    /// An 8x8 logical screen with a solid-orange 4x4 frame at offset (2,2). The uncovered area must
    /// be left fully transparent (matching CoreGraphics, which ignores the background index for the
    /// first frame), and only the 4x4 region opaque.
    @Test func compositesSubScreenFrameOntoTransparentScreen() throws {
        let bytes: [UInt8] = [
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x08, 0x00, 0x08, 0x00, 0xF0, 0x00, 0x00,
            0xFF, 0x80, 0x00, 0x00, 0x00, 0x00,
            0x21, 0xF9, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x2C, 0x02, 0x00, 0x02, 0x00, 0x04, 0x00, 0x04, 0x00, 0x00,
            0x02, 0x04, 0x84, 0x8F, 0x09, 0x05, 0x00, 0x3B,
        ]
        let image = try ImageDecoder.decode(bytes)
        #expect(image.width == 8 && image.height == 8)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let i = (y * 8 + x) * 4
            return Array(image.data[i ..< i + 4])
        }
        #expect(pixel(0, 0) == [0, 0, 0, 0]) // uncovered: transparent
        #expect(pixel(7, 7) == [0, 0, 0, 0]) // uncovered: transparent
        #expect(pixel(3, 3) == [255, 128, 0, 255]) // inside the frame: opaque orange
        let opaque = (0 ..< 64).filter { image.data[$0 * 4 + 3] == 255 }.count
        #expect(opaque == 16) // exactly the 4x4 frame
    }

    /// Malformed/crafted GIFs must throw a catchable `ImageDecoder.Error`, never trap (the test
    /// completing without crashing is itself the proof).
    @Test(arguments: [
        [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], // signature only, header truncated
        [0x47, 0x49, 0x46, 0x38, 0x38, 0x61, 0, 0, 0, 0, 0, 0, 0], // "GIF88a": unknown version
        // Valid header (4x4, no global color table) then an immediate trailer: no image.
        [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x04, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x3B],
        // Global color table flag set but the table is truncated.
        [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x02, 0x00, 0x02, 0x00, 0x80, 0x00, 0x00, 0xFF, 0x00],
        // Image descriptor with LZW min code size but no data sub-blocks (truncated).
        [
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x02, 0x00, 0x02, 0x00, 0x80, 0x00, 0x00,
            0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
            0x2C, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x02, 0x00, 0x00, 0x02,
        ],
        // A 4x2 frame whose LZW stream ends after one pixel (clear + one literal): too few indices,
        // which must throw rather than zero-pad the rest.
        [
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x04, 0x00, 0x02, 0x00, 0xF1, 0x03, 0x00,
            0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
            0x2C, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x02, 0x00, 0x00,
            0x02, 0x01, 0x04, 0x00, 0x3B,
        ],
        // A 2x1 frame with a 2-entry palette but pixels referencing indices 2 and 3 (out of range):
        // a spec violation that must throw, not emit guessed colors.
        [
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x02, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
            0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00,
            0x2C, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00,
            0x02, 0x02, 0xD4, 0x0A, 0x00, 0x3B,
        ],
    ] as [[UInt8]])
    func rejectsMalformedWithoutTrapping(bytes: [UInt8]) {
        #expect(throws: ImageDecoder.Error.self) {
            try ImageDecoder.decode(bytes)
        }
    }
}
