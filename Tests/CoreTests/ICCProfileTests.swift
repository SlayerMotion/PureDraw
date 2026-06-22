//
//  ICCProfileTests.swift
//  PureDraw
//

@testable import Core
import Foundation
import Testing

/// The ICC reader is verified against real-world profiles where they exist (the system ColorSync
/// profiles), checking spec invariants no self-written fixture could fake: the matrix columns sum to the
/// media white point, and a profile that uses the sRGB tone curve decodes the same as `SRGBTransfer`.
/// A malformed buffer is rejected.
struct ICCProfileTests {
    private let displayP3Path = "/System/Library/ColorSync/Profiles/Display P3.icc"

    private func systemProfile(_ path: String) -> [UInt8]? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return [UInt8](data)
    }

    @Test func parsesARealDisplayProfileHeaderAndMatrix() throws {
        guard let bytes = systemProfile(displayP3Path) else { return } // skip where the profile is absent
        let profile = try #require(ICCProfileReader().read(bytes))

        #expect(profile.deviceClass == "mntr")
        #expect(profile.colorSpace == "RGB ")
        #expect(profile.connectionSpace == "XYZ ")
        #expect(profile.isMatrixRGB)

        // Spec invariant: the three matrix columns sum to the media white point (RGB white -> PCS white).
        let red = try #require(profile.redColumn)
        let green = try #require(profile.greenColumn)
        let blue = try #require(profile.blueColumn)
        #expect(abs(red.x + green.x + blue.x - profile.whitePoint.x) <= 1e-3)
        #expect(abs(red.y + green.y + blue.y - profile.whitePoint.y) <= 1e-3)
        #expect(abs(red.z + green.z + blue.z - profile.whitePoint.z) <= 1e-3)

        // The media white is D50, the XYZ-PCS reference white.
        #expect(abs(profile.whitePoint.x - 0.9642) <= 1e-3)
        #expect(abs(profile.whitePoint.y - 1.0) <= 1e-3)
        #expect(abs(profile.whitePoint.z - 0.8249) <= 1e-3)
    }

    @Test func displayP3UsesTheSRGBToneCurve() throws {
        guard let bytes = systemProfile(displayP3Path) else { return }
        let profile = try #require(ICCProfileReader().read(bytes))
        let curve = try #require(profile.redCurve)
        // Display P3 shares the sRGB transfer; its parametric curve decodes the same (to the precision
        // the profile's s15Fixed16 parameters allow).
        for x in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(abs(curve.value(at: x) - SRGBTransfer.decode(x)) <= 1e-3)
        }
    }

    @Test func deviceWhiteMapsToTheMediaWhite() throws {
        guard let bytes = systemProfile(displayP3Path) else { return }
        let profile = try #require(ICCProfileReader().read(bytes))
        // RGB (1,1,1) through the curves and matrix is the media white point.
        let white = try #require(profile.toConnectionXYZ(red: 1, green: 1, blue: 1))
        #expect(abs(white.x - profile.whitePoint.x) <= 2e-3)
        #expect(abs(white.y - profile.whitePoint.y) <= 2e-3)
        #expect(abs(white.z - profile.whitePoint.z) <= 2e-3)
    }

    @Test func rejectsNonICCBytes() {
        #expect(ICCProfileReader().read([UInt8]("not an icc profile, just text padding ....".utf8)) == nil)
        #expect(ICCProfileReader().read([0, 1, 2, 3]) == nil)
    }
}
