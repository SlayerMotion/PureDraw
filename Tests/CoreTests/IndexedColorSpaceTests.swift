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
