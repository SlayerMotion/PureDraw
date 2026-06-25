#if canImport(CoreText)
    @testable import Core
    import CoreGraphics
    import CoreText
    import Foundation
    import Testing

    @Suite("ZZ morx probe")
    struct ZZMorxProbe {
        private static let fontPath = "/System/Library/Fonts/Supplemental/Khmer Sangam MN.ttf"

        @Test func morxVsCoreText() throws {
            guard let data = FileManager.default.contents(atPath: Self.fontPath),
                  let font = try? Font(data: [UInt8](data)),
                  let provider = CGDataProvider(data: data as CFData),
                  let cgFont = CGFont(provider)
            else {
                print("MORX PROBE: font missing")
                return
            }
            print("MORX PROBE hasMorx=\(font.hasMorx)")
            let ctFont = CTFontCreateWithGraphicsFont(cgFont, CGFloat(font.unitsPerEm), nil, nil)
            let key = NSAttributedString.Key(kCTFontAttributeName as String)

            let cases: [(String, [UInt32])] = [
                ("ka", [0x1780]),
                ("ka+coeng+ka", [0x1780, 0x17D2, 0x1780]),
                ("ka+17C4(oo)", [0x1780, 0x17C4]),
                ("ka+17C5(au)", [0x1780, 0x17C5]),
                ("ka+17BE(oe)", [0x1780, 0x17BE]),
                ("ka+sra-e(17C1)", [0x1780, 0x17C1]),
                ("ka+coeng+ro", [0x1780, 0x17D2, 0x179A]),
            ]
            for (label, scalars) in cases {
                let inputGlyphs = scalars.enumerated().compactMap { idx, s -> MorxGlyph? in
                    guard let u = Unicode.Scalar(s), let g = font.glyphIndex(for: u) else { return nil }
                    return MorxGlyph(glyphID: g, cluster: idx)
                }
                let mine = font.applyMorx(inputGlyphs).map(\.glyphID)

                let str = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0) }))
                let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: str, attributes: [key: ctFont]))
                var ct: [Int] = []
                for run in (CTLineGetGlyphRuns(ctLine) as? [CTRun]) ?? [] {
                    let c = CTRunGetGlyphCount(run)
                    var gg = [CGGlyph](repeating: 0, count: c)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: c), &gg)
                    ct.append(contentsOf: gg.map(Int.init))
                }
                print("MORX PROBE \(label): in=\(inputGlyphs.map(\.glyphID)) mine=\(mine) ct=\(ct) \(mine == ct ? "OK" : "DIFF")")
            }
        }
    }
#endif
