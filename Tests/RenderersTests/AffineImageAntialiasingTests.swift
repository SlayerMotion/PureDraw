//
//  AffineImageAntialiasingTests.swift
//  PureDraw
//

import Core
import Geometry
import Renderers
import Testing

/// Affine `drawImage` must antialias its destination edge under a transform:
/// `shouldAntialias` controls destination-edge coverage (subpixel supersampling),
/// while `interpolationQuality` controls source sampling. A non-integer placement
/// makes the image edge cross pixel boundaries (issue #97).
struct AffineImageAntialiasingTests {
    private func opaqueWhite() throws -> Image {
        try Image(width: 1, height: 1, data: [255, 255, 255, 255])
    }

    /// Renders an opaque square placed at a half-pixel offset and returns how many
    /// pixels carry partial alpha (a fractional-coverage edge).
    private func fractionalEdgePixels(antialiased: Bool, quality: InterpolationQuality = .high) throws -> Int {
        var context = GraphicsContext()
        context.setShouldAntialias(antialiased)
        context.setInterpolationQuality(quality)
        // Half-pixel translation: the square's edges land on x/y = n + 0.5, splitting
        // the boundary pixels.
        context.concatenate(.translation(x: 0.5, y: 0.5))
        try context.draw(opaqueWhite(), in: Rect(x: 4, y: 4, width: 8, height: 8))
        let image = try BitmapRenderer(width: 20, height: 20).render(context)
        var fractional = 0
        for index in stride(from: 3, to: image.data.count, by: 4) {
            let alpha = image.data[index]
            if alpha > 0, alpha < 255 { fractional += 1 }
        }
        return fractional
    }

    @Test func antialiasedEdgeHasFractionalCoverage() throws {
        #expect(try fractionalEdgePixels(antialiased: true) > 0)
    }

    @Test func nonAntialiasedEdgeStaysBinary() throws {
        // Every pixel is fully inside (255) or fully outside (0): no partial coverage.
        #expect(try fractionalEdgePixels(antialiased: false) == 0)
    }

    @Test func edgeCoverageIsSeparateFromInterpolationQuality() throws {
        // Destination-edge coverage applies even with nearest-neighbor source
        // sampling: the two controls are independent.
        #expect(try fractionalEdgePixels(antialiased: true, quality: .none) > 0)
    }
}
