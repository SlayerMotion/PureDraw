//
//  ICCProfileRoundTripTests.swift
//  PureDraw
//

@testable import Core
import Testing

/// The ICC writer produces a spec-valid matrix-RGB profile that the reader recovers. The byte-level
/// checks ground the writer against the ICC spec (the `acsp` signature at offset 36, the profile size
/// in the header) so the round trip is not merely self-consistent, and the read-back recovers the
/// matrix and gamma to the precision the s15Fixed16 / u8Fixed8 encodings allow.
struct ICCProfileRoundTripTests {
    private let red = XYZColor(x: 0.436, y: 0.222, z: 0.014)
    private let green = XYZColor(x: 0.385, y: 0.717, z: 0.097)
    private let blue = XYZColor(x: 0.143, y: 0.061, z: 0.714)

    private func written(gamma: Double = 2.2) -> [UInt8] {
        ICCProfileWriter().write(redColumn: red, greenColumn: green, blueColumn: blue, gamma: gamma)
    }

    @Test func emitsSpecRequiredHeaderBytes() {
        let bytes = written()
        // The profile signature 'acsp' sits at offset 36, and the header size field equals the length.
        #expect(String(decoding: bytes[36 ..< 40], as: UTF8.self) == "acsp")
        let size = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        #expect(Int(size) == bytes.count)
        #expect(String(decoding: bytes[12 ..< 16], as: UTF8.self) == "mntr")
        #expect(String(decoding: bytes[16 ..< 20], as: UTF8.self) == "RGB ")
        #expect(String(decoding: bytes[20 ..< 24], as: UTF8.self) == "XYZ ")
    }

    @Test func readerRecoversTheWrittenMatrixAndGamma() throws {
        let profile = try #require(ICCProfileReader().read(written(gamma: 2.2)))
        #expect(profile.deviceClass == "mntr")
        #expect(profile.colorSpace == "RGB ")
        #expect(profile.isMatrixRGB)

        let r = try #require(profile.redColumn)
        let g = try #require(profile.greenColumn)
        let b = try #require(profile.blueColumn)
        // s15Fixed16 resolves to ~1.5e-5.
        #expect(abs(r.x - red.x) <= 1e-4 && abs(r.y - red.y) <= 1e-4 && abs(r.z - red.z) <= 1e-4)
        #expect(abs(g.x - green.x) <= 1e-4 && abs(g.y - green.y) <= 1e-4 && abs(g.z - green.z) <= 1e-4)
        #expect(abs(b.x - blue.x) <= 1e-4 && abs(b.y - blue.y) <= 1e-4 && abs(b.z - blue.z) <= 1e-4)

        // u8Fixed8 resolves gamma to 1/256; 2.2 round-trips within that.
        guard case let .gamma(gamma)? = profile.redCurve else {
            Issue.record("expected a gamma curve")
            return
        }
        #expect(abs(gamma - 2.2) <= 1.0 / 256.0)
    }

    @Test func writtenColumnsSumToTheWhitePointWhenBalanced() throws {
        // A grey-balanced matrix (columns chosen to sum to D50) keeps the white-point invariant.
        let d50 = XYZColor(x: 0.9642, y: 1.0, z: 0.8249)
        let third = XYZColor(x: d50.x / 3, y: d50.y / 3, z: d50.z / 3)
        let bytes = ICCProfileWriter().write(redColumn: third, greenColumn: third, blueColumn: third, gamma: 1)
        let profile = try #require(ICCProfileReader().read(bytes))
        let white = try #require(profile.toConnectionXYZ(red: 1, green: 1, blue: 1))
        #expect(abs(white.x - d50.x) <= 1e-3 && abs(white.y - d50.y) <= 1e-3 && abs(white.z - d50.z) <= 1e-3)
    }
}
