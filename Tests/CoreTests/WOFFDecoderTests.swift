#if canImport(Compression) // the Apple Compression oracle is Apple-only; these cross-checks skip elsewhere
//
    //  WOFFDecoderTests.swift
    //  PureDraw
//
    //  WOFF 1.0 decoding (PureDraw #75): a WOFF is wrapped here from a known sfnt (the minimal
    //  font FontTests builds), decoded back, and verified to parse to the same glyph -- both with
    //  stored tables and with a zlib-compressed table (compressed via the system codec, since the
    //  library ships only the inflate half). A separate compressed-table round-trip confirms the
    //  inflate branch and the sfnt reassembly directly.
//

    import Compression
    import Core
    import Foundation
    import Testing

    struct WOFFDecoderTests {
        @Test func decodesStoredWOFFToParseableFont() throws {
            let sfnt = MiniFont.build()
            let woff = buildWOFF(tables: sfntTables(sfnt), compress: [])
            let reference = try Font(data: sfnt)
            let decoded = try Font(woff: woff)
            let glyph = try #require(decoded.glyphIndex(for: "A"))
            #expect(decoded.glyphIndex(for: "A") == reference.glyphIndex(for: "A"))
            #expect(try decoded.outline(forGlyph: glyph) == reference.outline(forGlyph: #require(reference.glyphIndex(for: "A"))))
        }

        @Test func decodesCompressedTableRoundTrip() throws {
            // A large, highly compressible table guarantees the compressed branch (compLength <
            // origLength) is exercised; decoding must reproduce the exact table bytes.
            let payload = [UInt8](repeating: 0xAB, count: 400) + Array(0 ..< 100).map { UInt8($0) }
            let woff = buildWOFF(tables: [(tag: "TEST", data: payload), (tag: "head", data: minimalHead())], compress: ["TEST"])
            let sfnt = try WOFFDecoder.sfnt(from: woff)
            let table = try #require(tableData(in: sfnt, tag: "TEST"))
            #expect(table == payload, "the compressed table must inflate to its exact original bytes")
        }

        @Test func rejectsNonWOFF() {
            #expect(throws: WOFFDecoder.Error.notWOFF) { _ = try WOFFDecoder.sfnt(from: MiniFont.build()) }
            #expect(throws: WOFFDecoder.Error.self) { _ = try WOFFDecoder.sfnt(from: [UInt8](repeating: 0, count: 4)) }
        }

        // MARK: - WOFF assembly + sfnt parsing helpers

        private func sfntTables(_ sfnt: [UInt8]) -> [(tag: String, data: [UInt8])] {
            let numTables = Int(sfnt[4]) << 8 | Int(sfnt[5])
            var tables: [(String, [UInt8])] = []
            for i in 0 ..< numTables {
                let rec = 12 + i * 16
                let tag = String(decoding: sfnt[rec ..< rec + 4], as: UTF8.self)
                let offset = beUInt32(sfnt, rec + 8), length = beUInt32(sfnt, rec + 12)
                tables.append((tag, Array(sfnt[offset ..< offset + length])))
            }
            return tables
        }

        private func tableData(in sfnt: [UInt8], tag: String) -> [UInt8]? {
            let numTables = Int(sfnt[4]) << 8 | Int(sfnt[5])
            for i in 0 ..< numTables {
                let rec = 12 + i * 16
                if String(decoding: sfnt[rec ..< rec + 4], as: UTF8.self) == tag {
                    let offset = beUInt32(sfnt, rec + 8), length = beUInt32(sfnt, rec + 12)
                    return Array(sfnt[offset ..< offset + length])
                }
            }
            return nil
        }

        private func buildWOFF(tables: [(tag: String, data: [UInt8])], compress: Set<String>, flavor: UInt32 = 0x0001_0000) -> [UInt8] {
            struct Entry { let tag: [UInt8]
                let payload: [UInt8]
                let origLength: Int
            }
            var entries: [Entry] = []
            for t in tables {
                var payload = t.data
                if compress.contains(t.tag) {
                    let z = zlibCompress(t.data)
                    if z.count < t.data.count { payload = z } // WOFF stores when compression does not help
                }
                entries.append(Entry(tag: Array(t.tag.utf8), payload: payload, origLength: t.data.count))
            }

            var directory: [UInt8] = []
            var data: [UInt8] = []
            var offset = 44 + entries.count * 20
            for e in entries {
                directory += e.tag
                directory += be32(offset) + be32(e.payload.count) + be32(e.origLength) + be32(0) // offset, compLen, origLen, checksum
                data += e.payload
                offset += e.payload.count
            }

            var woff: [UInt8] = []
            woff += be32(0x774F_4646) // 'wOFF'
            woff += be32(Int(flavor)) // flavor (sfnt version)
            woff += be32(44 + directory.count + data.count) // total length
            woff += be16(entries.count) + be16(0) // numTables, reserved
            woff += be32(0) // totalSfntSize (unused by the decoder)
            woff += be16(1) + be16(0) // major/minor version
            woff += be32(0) + be32(0) + be32(0) // meta offset/length/origLength
            woff += be32(0) + be32(0) // priv offset/length
            woff += directory
            woff += data
            return woff
        }

        private func minimalHead() -> [UInt8] {
            // A 54-byte head table is enough for Font's directory walk in the round-trip test.
            [UInt8](repeating: 0, count: 54)
        }

        private func zlibCompress(_ data: [UInt8]) -> [UInt8] {
            let cap = data.count + 128
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
            defer { dst.deallocate() }
            let n = data.withUnsafeBufferPointer { src -> Int in
                guard let base = src.baseAddress else { return 0 }
                return compression_encode_buffer(dst, cap, base, data.count, nil, COMPRESSION_ZLIB)
            }
            var out: [UInt8] = [0x78, 0x01]
            out += Array(UnsafeBufferPointer(start: dst, count: n))
            var a: UInt32 = 1, b: UInt32 = 0
            for byte in data {
                a = (a + UInt32(byte)) % 65521
                b = (b + a) % 65521
            }
            let adler = b << 16 | a
            out += [UInt8(adler >> 24 & 0xFF), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]
            return out
        }

        private func beUInt32(_ b: [UInt8], _ o: Int) -> Int {
            Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
        }

        private func be32(_ v: Int) -> [UInt8] {
            [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
        }

        private func be16(_ v: Int) -> [UInt8] {
            [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
        }
    }
#endif
