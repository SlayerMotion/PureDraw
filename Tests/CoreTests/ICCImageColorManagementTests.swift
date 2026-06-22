//
//  ICCImageColorManagementTests.swift
//  PureDraw
//

@testable import Core
import Testing

/// Colour-managing an image applies the ICC profile-to-profile conversion to every pixel. These check
/// that converting through identical profiles leaves the image unchanged, and that each output pixel is
/// the converter applied to the matching input pixel.
struct ICCImageColorManagementTests {
    /// Two grey-balanced gamma-2.2 matrix profiles with slightly different primaries.
    private func profileA() throws -> ICCProfile {
        let bytes = ICCProfileWriter().write(
            redColumn: XYZColor(x: 0.45, y: 0.24, z: 0.02),
            greenColumn: XYZColor(x: 0.35, y: 0.69, z: 0.11),
            blueColumn: XYZColor(x: 0.1642, y: 0.07, z: 0.6949),
            gamma: 2.2
        )
        return try #require(ICCProfileReader().read(bytes))
    }

    private func profileB() throws -> ICCProfile {
        let bytes = ICCProfileWriter().write(
            redColumn: XYZColor(x: 0.49, y: 0.27, z: 0.01),
            greenColumn: XYZColor(x: 0.31, y: 0.67, z: 0.09),
            blueColumn: XYZColor(x: 0.1742, y: 0.06, z: 0.7149),
            gamma: 2.2
        )
        return try #require(ICCProfileReader().read(bytes))
    }

    /// A 2x2 opaque, near-neutral image (premultiplied RGBA, alpha 255 so straight equals premultiplied).
    private func testImage() throws -> Image {
        let data: [UInt8] = [
            128, 128, 128, 255,
            100, 120, 140, 255,
            180, 170, 160, 255,
            90, 110, 100, 255,
        ]
        return try Image(width: 2, height: 2, colorSpace: .deviceRGB, alphaInfo: .premultipliedLast, data: data)
    }

    @Test func identityProfilesLeaveTheImageUnchanged() throws {
        let image = try testImage()
        let profile = try profileA()
        let managed = try #require(image.colorManaged(from: profile, to: profile))
        for y in 0 ..< 2 {
            for x in 0 ..< 2 {
                let before = image.pixelColor(x: x, y: y)
                let after = managed.pixelColor(x: x, y: y)
                #expect(abs(before.red - after.red) <= 0.01)
                #expect(abs(before.green - after.green) <= 0.01)
                #expect(abs(before.blue - after.blue) <= 0.01)
            }
        }
    }

    @Test func eachPixelIsTheConverterApplied() throws {
        let image = try testImage()
        let a = try profileA(), b = try profileB()
        let managed = try #require(image.colorManaged(from: a, to: b))
        for y in 0 ..< 2 {
            for x in 0 ..< 2 {
                let source = image.pixelColor(x: x, y: y)
                let expected = try #require(a.convert(red: source.red, green: source.green, blue: source.blue, to: b))
                let actual = managed.pixelColor(x: x, y: y)
                // Within 8-bit byte rounding of the converter's result.
                #expect(abs(actual.red - expected.red) <= 1.0 / 255.0 + 1e-9)
                #expect(abs(actual.green - expected.green) <= 1.0 / 255.0 + 1e-9)
                #expect(abs(actual.blue - expected.blue) <= 1.0 / 255.0 + 1e-9)
            }
        }
    }

    @Test func rejectsNonMatrixProfiles() throws {
        // A profile with no matrix columns cannot colour-manage.
        let empty = ICCProfile(
            deviceClass: "mntr", colorSpace: "RGB ", connectionSpace: "XYZ ",
            renderingIntent: 1, whitePoint: XYZColor(x: 0.9642, y: 1.0, z: 0.8249)
        )
        #expect(try testImage().colorManaged(from: empty, to: profileA()) == nil)
    }
}
