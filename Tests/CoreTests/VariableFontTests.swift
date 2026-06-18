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

        /// Interpolates real glyph outlines (both simple and composite) along the weight axis and
        /// checks each against CoreText's own instanced path (CTFontCreatePathForGlyph). The test
        /// requires several glyphs to be compared so it cannot pass vacuously, and asserts that almost
        /// no glyph CoreText varies is left flat by the parser (which would signal broken variation).
        @Test func gvarOutlineMatchesCoreText() throws {
            let path = "/System/Library/Fonts/NewYork.ttf"
            guard let data = FileManager.default.contents(atPath: path) else { return }
            let font = try Font(data: [UInt8](data))
            guard let weight = font.variationAxes.first(where: { $0.tag == "wght" }),
                  let provider = CGDataProvider(data: data as CFData), let cgFont = CGFont(provider)
            else { return }

            let upm = Double(font.unitsPerEm)
            let target = (weight.defaultValue + weight.maxValue) / 2
            let variations = ["wght": target]
            let axisID = fourCharInt("wght")
            let tolerance = 3.0 // font units; correct interpolation differs only by fixed-point rounding

            // A mix of simple glyphs and accented letters (built as composites in this font), so both
            // the simple-contour and composite-offset variation paths are exercised against CoreText.
            var compared = 0
            var coreTextVariedButFlat = 0 // CoreText varies it but the parser does not (should be rare)
            for scalar in "HILTEFowlmnu1470áàâäéèêëíîïóôöúûüñç".unicodeScalars {
                guard let glyph = font.glyphIndex(for: scalar),
                      let mineInstance = font.outline(forGlyph: glyph, variations: variations),
                      let mineDefault = font.outline(forGlyph: glyph),
                      let ctInstance = ctGlyphPath(cgFont, glyph: glyph, size: upm, axis: axisID, value: target),
                      let ctDefault = ctGlyphPath(cgFont, glyph: glyph, size: upm, axis: axisID, value: weight.defaultValue)
                else { continue }

                let ctVaried = boxDistance(ctInstance.boundingBoxOfPath, ctDefault.boundingBoxOfPath) > tolerance
                let myVaried = hausdorff(pathPoints(mineInstance), pathPoints(mineDefault)) > tolerance
                guard ctVaried else { continue } // glyph is invariant under weight: nothing to check
                if !myVaried { coreTextVariedButFlat += 1
                    continue
                } // only point-matched composites should land here

                let myPoints = pathPoints(mineInstance)
                let ctPoints = cgPathPoints(ctInstance)
                #expect(hausdorff(myPoints, ctPoints) < tolerance, "glyph \(glyph): outline diverges from CoreText")
                #expect(hausdorff(ctPoints, myPoints) < tolerance, "glyph \(glyph): CoreText has points the outline misses")

                let myBox = boundingBox(myPoints)
                let ctBox = ctInstance.boundingBoxOfPath
                #expect(boxDistance(myBox, ctBox) < tolerance, "glyph \(glyph): bounds diverge from CoreText")

                // At the default instance the interpolation must be a no-op.
                #expect(font.outline(forGlyph: glyph, variations: [:]) == mineDefault, "default instance must equal the static outline")
                compared += 1
            }
            #expect(compared >= 4, "expected to compare several varied glyphs against CoreText")
            #expect(coreTextVariedButFlat <= 1, "CoreText varies glyphs the parser leaves flat: composite variation may be broken")
        }

        /// CFF2 outlines (PureDraw #78): the CFF2-flavored variable font `SFIndia.ttc` is parsed and
        /// its glyph outlines (at the default instance) are checked against CoreText's own paths for
        /// the same face, confirming the CFF2 structure parse and the Type 2 charstring interpreter.
        @Test func cff2OutlineMatchesCoreText() throws {
            let path = "/System/Library/Fonts/SFIndia.ttc"
            guard let data = FileManager.default.contents(atPath: path) else { return }
            let font = try Font(data: [UInt8](data))
            guard let provider = CGDataProvider(data: data as CFData), let cgFont = CGFont(provider) else { return }
            let upm = Double(font.unitsPerEm)
            let ctFont = CTFontCreateWithGraphicsFont(cgFont, CGFloat(upm), nil, nil)
            let tolerance = max(2.0, upm * 0.01)

            // SFIndia is an Indic-script font (no Latin cmap), so iterate glyph indices directly.
            var compared = 0
            for glyph in 1 ..< min(120, font.numberOfGlyphs) {
                guard let mine = font.outline(forGlyph: glyph),
                      let ct = CTFontCreatePathForGlyph(ctFont, CGGlyph(glyph), nil)
                else { continue }
                let myPoints = pathPoints(mine)
                let ctPoints = cgPathPoints(ct)
                guard myPoints.count > 3, ctPoints.count > 3 else { continue }
                #expect(hausdorff(myPoints, ctPoints) < tolerance, "glyph \(glyph): CFF2 outline diverges from CoreText")
                #expect(hausdorff(ctPoints, myPoints) < tolerance, "glyph \(glyph): CoreText has CFF2 points the parser misses")
                compared += 1
                if compared >= 12 { break }
            }
            #expect(compared >= 6, "expected to compare several CFF2 glyphs against CoreText")
        }

        private func ctGlyphPath(_ cgFont: CGFont, glyph: Int, size: Double, axis: Int, value: Double) -> CGPath? {
            let attributes = [kCTFontVariationAttribute: [axis: value]] as CFDictionary
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes)
            let ctFont = CTFontCreateWithGraphicsFont(cgFont, CGFloat(size), nil, descriptor)
            return CTFontCreatePathForGlyph(ctFont, CGGlyph(glyph), nil)
        }

        private func fourCharInt(_ tag: String) -> Int {
            tag.utf8.reduce(0) { ($0 << 8) | Int($1) }
        }

        private func pathPoints(_ path: Path) -> [CGPoint] {
            var points: [CGPoint] = []
            for element in path.elements {
                switch element {
                case let .move(to), let .line(to):
                    points.append(CGPoint(x: to.x, y: to.y))
                case let .quadCurve(to, control):
                    points.append(CGPoint(x: to.x, y: to.y))
                    points.append(CGPoint(x: control.x, y: control.y))
                case let .cubicCurve(to, control1, control2):
                    points.append(CGPoint(x: to.x, y: to.y))
                    points.append(CGPoint(x: control1.x, y: control1.y))
                    points.append(CGPoint(x: control2.x, y: control2.y))
                case .close:
                    break
                }
            }
            return points
        }

        private func cgPathPoints(_ path: CGPath) -> [CGPoint] {
            var points: [CGPoint] = []
            path.applyWithBlock { elementPointer in
                let element = elementPointer.pointee
                switch element.type {
                case .moveToPoint, .addLineToPoint:
                    points.append(element.points[0])
                case .addQuadCurveToPoint:
                    points.append(element.points[0])
                    points.append(element.points[1])
                case .addCurveToPoint:
                    points.append(element.points[0])
                    points.append(element.points[1])
                    points.append(element.points[2])
                case .closeSubpath:
                    break
                @unknown default:
                    break
                }
            }
            return points
        }

        /// The largest distance from any point in `a` to its nearest neighbor in `b` (a directed
        /// Hausdorff distance), which is insensitive to point order and contour start.
        private func hausdorff(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
            guard !b.isEmpty else { return .greatestFiniteMagnitude }
            var worst = 0.0
            for p in a {
                var nearest = Double.greatestFiniteMagnitude
                for q in b {
                    nearest = min(nearest, hypot(Double(p.x - q.x), Double(p.y - q.y)))
                }
                worst = max(worst, nearest)
            }
            return worst
        }

        private func boundingBox(_ points: [CGPoint]) -> CGRect {
            guard let first = points.first else { return .zero }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in points {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        private func boxDistance(_ a: CGRect, _ b: CGRect) -> Double {
            max(
                max(abs(Double(a.minX - b.minX)), abs(Double(a.minY - b.minY))),
                max(abs(Double(a.maxX - b.maxX)), abs(Double(a.maxY - b.maxY)))
            )
        }
    }
#endif
