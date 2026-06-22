//
//  ICCColorConversionTests.swift
//  PureDraw
//

@testable import Core
import Foundation
import Testing

/// Colour-managed conversion through ICC profiles: device RGB to the PCS and back, and between two
/// profiles. Verified against real system profiles where present (the inverse must undo the forward
/// transform, and converting between two profiles must round-trip), plus a portable written-profile
/// identity that needs no system files.
struct ICCColorConversionTests {
    private let samples: [(Double, Double, Double)] = [
        (0.2, 0.4, 0.6), (0.9, 0.1, 0.3), (0.5, 0.5, 0.5), (0.13, 0.77, 0.42), (0.8, 0.8, 0.2),
    ]

    private func systemProfile(_ name: String) -> ICCProfile? {
        let path = "/System/Library/ColorSync/Profiles/\(name)"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return ICCProfileReader().read([UInt8](data))
    }

    @Test func forwardThenInverseIsIdentityForARealProfile() throws {
        guard let p3 = systemProfile("Display P3.icc") else { return }
        for (r, g, b) in samples {
            let xyz = try #require(p3.toConnectionXYZ(red: r, green: g, blue: b))
            let back = try #require(p3.fromConnectionXYZ(xyz))
            #expect(abs(back.red - r) <= 1e-3 && abs(back.green - g) <= 1e-3 && abs(back.blue - b) <= 1e-3)
        }
    }

    @Test func convertingAProfileToItselfIsIdentity() throws {
        guard let p3 = systemProfile("Display P3.icc") else { return }
        for (r, g, b) in samples {
            let converted = try #require(p3.convert(red: r, green: g, blue: b, to: p3))
            #expect(abs(converted.red - r) <= 1e-3 && abs(converted.green - g) <= 1e-3 && abs(converted.blue - b) <= 1e-3)
        }
    }

    @Test func crossProfileConversionRoundTrips() throws {
        guard let p3 = systemProfile("Display P3.icc"), let adobe = systemProfile("AdobeRGB1998.icc") else { return }
        // Near-neutral colours lie inside every RGB gamut, so no gamut clamping intervenes and
        // P3 -> Adobe RGB -> P3 is the identity (both are matrix profiles in the same D50 PCS). A
        // saturated colour outside the destination gamut would legitimately clamp, which is colorimetric
        // intent, not a round-trip failure.
        let neutralish: [(Double, Double, Double)] = [
            (0.5, 0.5, 0.5), (0.3, 0.3, 0.32), (0.7, 0.68, 0.7), (0.45, 0.5, 0.48), (0.6, 0.55, 0.5),
        ]
        for (r, g, b) in neutralish {
            let inAdobe = try #require(p3.convert(red: r, green: g, blue: b, to: adobe))
            // The intermediate stays in gamut (no clamping at the boundary).
            #expect(inAdobe.red > 0 && inAdobe.red < 1 && inAdobe.green > 0 && inAdobe.green < 1)
            let back = try #require(adobe.convert(red: inAdobe.red, green: inAdobe.green, blue: inAdobe.blue, to: p3))
            #expect(abs(back.red - r) <= 2e-3 && abs(back.green - g) <= 2e-3 && abs(back.blue - b) <= 2e-3)
        }
    }

    @Test func writtenProfileIdentityIsPortable() throws {
        // A grey-balanced gamma-2.2 profile, no system files needed.
        let d50 = XYZColor(x: 0.9642, y: 1.0, z: 0.8249)
        let red = XYZColor(x: 0.45, y: 0.24, z: 0.02)
        let green = XYZColor(x: 0.35, y: 0.69, z: 0.11)
        let blue = XYZColor(x: d50.x - 0.45 - 0.35, y: d50.y - 0.24 - 0.69, z: d50.z - 0.02 - 0.11)
        let bytes = ICCProfileWriter().write(redColumn: red, greenColumn: green, blueColumn: blue, gamma: 2.2)
        let profile = try #require(ICCProfileReader().read(bytes))

        for (r, g, b) in samples {
            let xyz = try #require(profile.toConnectionXYZ(red: r, green: g, blue: b))
            let back = try #require(profile.fromConnectionXYZ(xyz))
            #expect(abs(back.red - r) <= 1e-3 && abs(back.green - g) <= 1e-3 && abs(back.blue - b) <= 1e-3)
        }
    }
}
