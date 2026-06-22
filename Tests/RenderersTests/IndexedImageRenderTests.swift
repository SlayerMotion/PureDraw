//
//  IndexedImageRenderTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// An indexed image renders through the whole pipeline: `BitmapRenderer` samples it via `pixelColor`,
/// which resolves each index to its palette color, so the rasterized pixels are the palette entries.
struct IndexedImageRenderTests {
    @Test func indexedImagePaintsPaletteColors() throws {
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
        let space = IndexedColorSpace(base: .deviceRGB, palette: [red, blue])
        // A 2x1 indexed image: left = palette[0] (red), right = palette[1] (blue).
        let image = try Image(
            width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
            colorSpace: .deviceRGB, alphaInfo: .none, indexedColorSpace: space, data: [0, 1]
        )

        var context = GraphicsContext()
        context.draw(image, in: Rect(x: 0, y: 0, width: 2, height: 1))
        let out = try BitmapRenderer(width: 2, height: 1).draw(context).data

        // RGBA8, premultiplied; opaque palette so premultiplied equals straight.
        // Left pixel red, right pixel blue.
        #expect(out[0] == 255) // R of left
        #expect(out[2] == 0) // B of left
        #expect(out[4] == 0) // R of right
        #expect(out[6] == 255) // B of right
    }
}
