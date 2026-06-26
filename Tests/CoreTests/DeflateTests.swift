//
//  DeflateTests.swift
//  PureDraw
//
//  Hermetic, dependency-free coverage of the DEFLATE compressor. Correctness is pinned by the
//  round-trip invariant: anything `Deflate.compressed` produces, `Inflate` must decode back to the
//  exact input (and `Inflate` is itself checked against the system zlib elsewhere). Separate tests
//  pin that real data actually shrinks and that incompressible data never blows up past a stored
//  encoding.
//

@testable import Core
import Testing

struct DeflateTests {
    /// A small linear-congruential generator so "random" (incompressible) inputs are deterministic
    /// without pulling in Foundation.
    private func pseudoRandom(count: Int, seed: UInt64 = 0x2545_F491_4F6C_DD1D) -> [UInt8] {
        var state = seed
        var out = [UInt8](repeating: 0, count: count)
        for i in 0 ..< count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            out[i] = UInt8((state >> 33) & 0xFF)
        }
        return out
    }

    private func roundTrips(_ data: [UInt8]) -> Bool {
        guard let restored = Inflate.deflate(Deflate.compressed(data)) else { return false }
        return restored == data
    }

    @Test func roundTripsEdgeCases() {
        #expect(roundTrips([]))
        #expect(roundTrips([0x00]))
        #expect(roundTrips([0xFF]))
        #expect(roundTrips([0x01, 0x02, 0x03]))
        #expect(roundTrips(Array("the quick brown fox".utf8)))
    }

    @Test func roundTripsRepetitiveData() {
        #expect(roundTrips([UInt8](repeating: 0x42, count: 50000)))
        // A short repeating pattern exercises many back-references at small distances.
        #expect(roundTrips((0 ..< 20000).map { UInt8($0 % 7) }))
    }

    @Test func roundTripsIncompressibleData() {
        #expect(roundTrips(pseudoRandom(count: 40000)))
        #expect(roundTrips(pseudoRandom(count: 1)))
    }

    @Test func roundTripsImageLikeData() {
        // RGBA gradient scanlines, each prefixed by a PNG filter byte: the realistic input.
        var raw: [UInt8] = []
        for y in 0 ..< 128 {
            raw.append(0)
            for x in 0 ..< 128 {
                raw.append(UInt8(x * 2 % 256))
                raw.append(UInt8(y * 2 % 256))
                raw.append(UInt8((x + y) % 256))
                raw.append(255)
            }
        }
        #expect(roundTrips(raw))
    }

    @Test func actuallyCompressesRepetitiveData() {
        let data = [UInt8](repeating: 0x42, count: 50000)
        let compressed = Deflate.compressed(data)
        // A 50 KB run of one byte must collapse dramatically (matches cover most of it).
        #expect(compressed.count < data.count / 20)
    }

    @Test func incompressibleDataNeverBlowsUp() {
        // Random data cannot shrink; the stored-block fallback bounds the overhead to a few bytes per
        // 64 KB block, so the result stays within a small margin of the input.
        let data = pseudoRandom(count: 40000)
        let compressed = Deflate.compressed(data)
        #expect(compressed.count <= data.count + 16)
    }
}
