//
//  VariableFontTests.swift
//  PureDraw
//
//  Variable-font fvar parsing (PureDraw #77): a from-spec fvar table (two axes, one named
//  instance) is attached to MiniFont and Font.variationAxes / .namedInstances must read back the
//  exact values; a static font reports no axes. A second, macOS-only check parses a real system
//  variable font and cross-checks the axes against CoreText (CTFontCopyVariationAxes), so the
//  parser is verified against ground truth and not only against a self-built fixture.
//

import Core
import Testing

struct VariableFontTests {
    @Test func parsesFvarAxesAndInstances() throws {
        let font = try Font(data: sfntWithFvar(MiniFont.build()))
        #expect(font.isVariable)
        #expect(font.variationAxes == [
            VariationAxis(tag: "wght", minValue: 100, defaultValue: 400, maxValue: 900, nameID: 256),
            VariationAxis(tag: "wdth", minValue: 50, defaultValue: 100, maxValue: 200, nameID: 257),
        ])
        #expect(font.namedInstances == [
            VariationInstance(subfamilyNameID: 258, coordinates: [700, 75], postScriptNameID: nil),
        ])

        let plain = try Font(data: MiniFont.build())
        #expect(!plain.isVariable)
        #expect(plain.variationAxes.isEmpty)
        #expect(plain.namedInstances.isEmpty)
    }

    // MARK: - fvar + sfnt assembly

    private func sfntWithFvar(_ sfnt: [UInt8]) -> [UInt8] {
        // fvar header (16) + 2 axis records (20 each) + 1 instance record (4 + 2 coords * 4).
        var fvar = be16(1) + be16(0) // major, minor
        fvar += be16(16) // axesArrayOffset
        fvar += be16(2) // reserved
        fvar += be16(2) + be16(20) // axisCount, axisSize
        fvar += be16(1) + be16(12) // instanceCount, instanceSize (4 + 2*4, no PS name)
        fvar += axis("wght", 100, 400, 900, nameID: 256)
        fvar += axis("wdth", 50, 100, 200, nameID: 257)
        fvar += be16(258) + be16(0) + fixed(700) + fixed(75) // instance: subfamily, flags, coords

        var tables = sfntTables(sfnt)
        tables.append((tag: "fvar", data: fvar))
        return assembleSFNT(tables, flavor: 0x0001_0000)
    }

    private func axis(_ tag: String, _ min: Double, _ def: Double, _ max: Double, nameID: Int) -> [UInt8] {
        Array(tag.utf8) + fixed(min) + fixed(def) + fixed(max) + be16(0) + be16(nameID)
    }

    private func fixed(_ v: Double) -> [UInt8] {
        be32(Int((v * 65536).rounded()))
    }

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

    private func assembleSFNT(_ tables: [(tag: String, data: [UInt8])], flavor: Int) -> [UInt8] {
        let sorted = tables.sorted { $0.tag < $1.tag }
        var pow2 = 1, sel = 0
        while pow2 * 2 <= sorted.count {
            pow2 *= 2
            sel += 1
        }
        let searchRange = pow2 * 16
        var out = be32(flavor) + be16(sorted.count) + be16(searchRange) + be16(sel) + be16(sorted.count * 16 - searchRange)
        var offset = 12 + sorted.count * 16
        for t in sorted {
            out += Array(t.tag.utf8) + be32(0) + be32(offset) + be32(t.data.count)
            offset += (t.data.count + 3) & ~3
        }
        for t in sorted {
            out += t.data + [UInt8](repeating: 0, count: ((t.data.count + 3) & ~3) - t.data.count)
        }
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

#if canImport(CoreText)
    import CoreGraphics
    import CoreText
    import Foundation

    struct VariableFontCoreTextTests {
        /// Cross-checks the fvar parser against CoreText on a real system variable font. Skipped
        /// (returns) when the font is not present, so the suite stays portable.
        @Test func fvarMatchesCoreTextOnSystemFont() throws {
            let path = "/System/Library/Fonts/NewYork.ttf"
            guard let data = FileManager.default.contents(atPath: path) else { return }
            let font = try Font(data: [UInt8](data))
            #expect(font.isVariable)
            let axes = font.variationAxes
            #expect(!axes.isEmpty)

            guard let provider = CGDataProvider(data: data as CFData), let cgFont = CGFont(provider) else { return }
            let ctFont = CTFontCreateWithGraphicsFont(cgFont, 12, nil, nil)
            guard let ctAxes = CTFontCopyVariationAxes(ctFont) as? [[CFString: Any]] else { return }
            #expect(ctAxes.count == axes.count, "axis count must match CoreText")
            for ctAxis in ctAxes {
                guard let identifier = (ctAxis[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue,
                      let minV = (ctAxis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue,
                      let defV = (ctAxis[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue,
                      let maxV = (ctAxis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue
                else { continue }
                let tag = fourCharCode(identifier)
                let mine = try #require(axes.first { $0.tag == tag }, "parser is missing axis \(tag)")
                #expect(abs(mine.minValue - minV) < 0.01)
                #expect(abs(mine.defaultValue - defV) < 0.01)
                #expect(abs(mine.maxValue - maxV) < 0.01)
            }
        }

        private func fourCharCode(_ code: Int) -> String {
            let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
            return String(decoding: bytes, as: UTF8.self)
        }
    }
#endif
