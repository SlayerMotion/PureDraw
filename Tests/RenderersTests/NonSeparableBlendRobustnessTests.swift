//
//  NonSeparableBlendRobustnessTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

/// The W3C non-separable blend modes (hue/saturation/color/luminosity) transfer luminance
/// and saturation through `clipColor`, whose gamut-clip scaling divides by `l - n` and
/// `x - l`. For an ACHROMATIC colour (r == g == b) both denominators are 0. A transparent
/// backdrop pixel is achromatic black, and an image whose premultiplied storage violates
/// `rgb <= alpha` (a tint can produce this) unpremultiplies to a channel > 1, so the blend
/// evaluates `clipColor` on an achromatic out-of-gamut triple. The old code computed 0/0 ->
/// NaN there, and `NaN * blendedAlpha` (NaN even when blendedAlpha is 0) reached
/// `Int(round(NaN * 255))`, trapping the whole process. These cases prove it now degrades:
/// the guarded division leaves the achromatic colour unchanged, and the byte quantiser
/// clamps in Double space, so the render completes and the source composites visibly.
struct NonSeparableBlendRobustnessTests {
    /// A 4x4 image whose every pixel is premultiplied `(255, 255, 255, 128)`: stored RGB
    /// exceeds stored alpha, so it unpremultiplies to `2.0` per channel, out of gamut.
    private func outOfGamutPremultipliedImage() throws -> Image {
        let pixel: [UInt8] = [255, 255, 255, 128]
        return try Image(
            width: 4,
            height: 4,
            alphaInfo: .premultipliedLast,
            data: Array(repeating: pixel, count: 16).flatMap { $0 }
        )
    }

    /// Renders the out-of-gamut image under `mode` over a fresh (transparent black, hence
    /// achromatic) canvas. Returns the centre pixel's RGBA. Reaching this return at all is
    /// the regression proof: the old code trapped before any byte was written.
    private func centrePixel(_ mode: BlendMode) throws -> (r: Int, g: Int, b: Int, a: Int) {
        var context = GraphicsContext()
        context.setBlendMode(mode)
        try context.draw(outOfGamutPremultipliedImage(), in: Rect(x: 0, y: 0, width: 4, height: 4))
        let data = try BitmapRenderer(width: 4, height: 4).render(context).data
        let i = (2 * 4 + 2) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
    }

    @Test(arguments: [BlendMode.hue, .saturation, .color, .luminosity])
    func nonSeparableBlendOverTransparentDoesNotTrap(_ mode: BlendMode) throws {
        let p = try centrePixel(mode)
        // Every channel is a real byte (no trap reached this point), and over a transparent
        // backdrop the blend term drops out (blendedAlpha == 0), so the source composites
        // source-over: a visible, in-gamut, non-transparent pixel.
        #expect(p.a > 0, "\(mode): source must composite visibly over the transparent canvas")
        #expect((0 ... 255).contains(p.r) && (0 ... 255).contains(p.g) && (0 ... 255).contains(p.b))
    }
}
