//
//  IndexedColorSpaceTests.swift
//  PureDraw
//

@testable import Core
import Testing

/// An indexed color space resolves an 8-bit sample to a palette color. These assert the lookup, the
/// out-of-range clamp, the empty-palette fallback, and that an indexed `Image` decodes each sample
/// through its palette.
struct IndexedColorSpaceTests {
    private let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)

    @Test func resolvesIndexToPaletteColor() {
        let space = IndexedColorSpace(base: .deviceRGB, palette: [red, green, blue])
        #expect(space.color(at: 0) == red)
        #expect(space.color(at: 1) == green)
        #expect(space.color(at: 2) == blue)
    }

    @Test func clampsOutOfRangeIndex() {
        let space = IndexedColorSpace(base: .deviceRGB, palette: [red, green])
        #expect(space.color(at: 5) == green) // past the end clamps to the last entry
        #expect(space.color(at: -3) == red) // before the start clamps to the first entry
    }

    @Test func emptyPaletteIsClear() {
        let space = IndexedColorSpace(base: .deviceRGB, palette: [])
        #expect(space.color(at: 0) == .clear)
    }

    @Test func indexedImageDecodesEachSampleThroughThePalette() throws {
        // A 3x1 image whose samples 0,1,2 index a red/green/blue palette.
        let space = IndexedColorSpace(base: .deviceRGB, palette: [red, green, blue])
        let image = try Image(
            width: 3, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
            colorSpace: .deviceRGB, alphaInfo: .none, indexedColorSpace: space, data: [0, 1, 2]
        )
        #expect(image.pixelColor(x: 0, y: 0) == red)
        #expect(image.pixelColor(x: 1, y: 0) == green)
        #expect(image.pixelColor(x: 2, y: 0) == blue)
    }

    @Test func fourBitIndicesAreUnpackedMSBFirst() throws {
        let space = IndexedColorSpace(base: .deviceRGB, palette: [red, green, blue, Color(red: 1, green: 1, blue: 0, alpha: 1)])
        // 4 pixels, 4 bits each, 2 per byte MSB-first: indices 0,1,2,3 -> bytes 0x01, 0x23.
        let image = try Image(
            width: 4, height: 1, bitsPerComponent: 4, bitsPerPixel: 4,
            colorSpace: .deviceRGB, alphaInfo: .none, indexedColorSpace: space, data: [0x01, 0x23]
        )
        #expect(image.pixelColor(x: 0, y: 0) == space.color(at: 0))
        #expect(image.pixelColor(x: 1, y: 0) == space.color(at: 1))
        #expect(image.pixelColor(x: 2, y: 0) == space.color(at: 2))
        #expect(image.pixelColor(x: 3, y: 0) == space.color(at: 3))
    }

    @Test func oneBitIndicesAreUnpackedMSBFirst() throws {
        let space = IndexedColorSpace(base: .deviceRGB, palette: [red, green])
        // 4 pixels, 1 bit each, in one byte MSB-first: indices 1,0,1,0 -> 0b1010_0000 = 0xA0.
        let image = try Image(
            width: 4, height: 1, bitsPerComponent: 1, bitsPerPixel: 1,
            colorSpace: .deviceRGB, alphaInfo: .none, indexedColorSpace: space, data: [0xA0]
        )
        #expect(image.pixelColor(x: 0, y: 0) == green)
        #expect(image.pixelColor(x: 1, y: 0) == red)
        #expect(image.pixelColor(x: 2, y: 0) == green)
        #expect(image.pixelColor(x: 3, y: 0) == red)
    }

    @Test func twoBitIndicesAreUnpackedMSBFirst() throws {
        let yellow = Color(red: 1, green: 1, blue: 0, alpha: 1)
        let space = IndexedColorSpace(base: .deviceRGB, palette: [red, green, blue, yellow])
        // 4 pixels, 2 bits each, in one byte: indices 0,1,2,3 -> 0b00_01_10_11 = 0x1B.
        let image = try Image(
            width: 4, height: 1, bitsPerComponent: 2, bitsPerPixel: 2,
            colorSpace: .deviceRGB, alphaInfo: .none, indexedColorSpace: space, data: [0x1B]
        )
        #expect(image.pixelColor(x: 0, y: 0) == red)
        #expect(image.pixelColor(x: 1, y: 0) == green)
        #expect(image.pixelColor(x: 2, y: 0) == blue)
        #expect(image.pixelColor(x: 3, y: 0) == yellow)
    }

    @Test func subByteRowsArePaddedToAWholeByte() throws {
        // Width 3 at 1 bit needs 1 byte per row; the default bytesPerRow must round up, not truncate.
        let space = IndexedColorSpace(base: .deviceRGB, palette: [red, green])
        let image = try Image(
            width: 3, height: 2, bitsPerComponent: 1, bitsPerPixel: 1,
            colorSpace: .deviceRGB, alphaInfo: .none, indexedColorSpace: space, data: [0x80, 0x00]
        )
        #expect(image.bytesPerRow == 1)
        #expect(image.pixelColor(x: 0, y: 0) == green) // high bit of row 0 set
        #expect(image.pixelColor(x: 0, y: 1) == red) // row 1 all zero
    }

    @Test func paletteAlphaIsCarriedThrough() throws {
        // A transparent palette entry (the tRNS analog) needs no separate alpha channel.
        let translucent = Color(red: 1, green: 0, blue: 0, alpha: 0.25)
        let space = IndexedColorSpace(base: .deviceRGB, palette: [translucent])
        let image = try Image(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
            colorSpace: .deviceRGB, alphaInfo: .none, indexedColorSpace: space, data: [0]
        )
        #expect(image.pixelColor(x: 0, y: 0).alpha == 0.25)
    }
}
