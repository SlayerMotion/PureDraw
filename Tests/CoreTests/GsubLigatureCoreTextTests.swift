#if canImport(CoreText)
    @testable import Core
    import CoreGraphics
    import CoreText
    import Foundation
    import Testing

    /// A differential trip for GSUB ligature parsing: for a real system font that
    /// ligates via OpenType GSUB, take each two-component `liga` rule PureDraw
    /// parsed, reverse-map its components to characters, shape that string through
    /// Core Text, and assert Core Text forms the same ligature glyph PureDraw's rule
    /// says it should. The final assertion keeps the trip non-vacuous by requiring
    /// at least one rule confirmed against Core Text.
    @Suite("GSUB ligatures match Core Text (PureDraw#140)")
    struct GsubLigatureCoreTextTests {
        @Test func ligaturesMatchCoreTextOnSystemFont() {
            let candidates = [
                "/System/Library/Fonts/SFNS.ttf",
                "/System/Library/Fonts/SFNSRounded.ttf",
                "/System/Library/Fonts/SFNSMono.ttf",
            ]
            var confirmed = 0
            for path in candidates {
                guard let data = FileManager.default.contents(atPath: path),
                      let font = try? Font(data: [UInt8](data)),
                      let provider = CGDataProvider(data: data as CFData),
                      let cgFont = CGFont(provider)
                else {
                    continue
                }
                let ligatures = font.ligatures()
                guard !ligatures.isEmpty else { continue }
                let ctFont = CTFontCreateWithGraphicsFont(cgFont, CGFloat(font.unitsPerEm), nil, nil)
                let scalarForGlyph = reverseCmap(font)

                for rule in ligatures where rule.components.count == 2 {
                    guard let first = scalarForGlyph[rule.components[0]],
                          let second = scalarForGlyph[rule.components[1]]
                    else {
                        continue
                    }
                    let input = String(String.UnicodeScalarView([first, second]))
                    guard let coreTextGlyph = singleGlyph(input, font: ctFont) else { continue }
                    #expect(
                        coreTextGlyph == rule.ligatureGlyph,
                        "components \(rule.components): PureDraw \(rule.ligatureGlyph) vs Core Text \(coreTextGlyph)"
                    )
                    confirmed += 1
                    if confirmed >= 5 { break }
                }
                if confirmed > 0 { break }
            }
            #expect(confirmed > 0, "the trip must confirm at least one GSUB ligature against Core Text")
        }

        /// A glyph-to-scalar map over the printable range, so a ligature's component
        /// glyphs can be turned back into the characters that produce them.
        private func reverseCmap(_ font: Font) -> [Int: Unicode.Scalar] {
            var map: [Int: Unicode.Scalar] = [:]
            for value in 0x20 ... 0x2FFF {
                guard let scalar = Unicode.Scalar(value) else { continue }
                if let glyph = font.glyphIndex(for: scalar), map[glyph] == nil {
                    map[glyph] = scalar
                }
            }
            return map
        }

        /// Shapes `text` through Core Text and returns the single glyph it produced,
        /// or `nil` if the text did not ligate into exactly one glyph.
        private func singleGlyph(_ text: String, font ctFont: CTFont) -> Int? {
            let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
            let attributed = NSAttributedString(string: text, attributes: [fontKey: ctFont])
            let line = CTLineCreateWithAttributedString(attributed)
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], runs.count == 1 else { return nil }
            let run = runs[0]
            guard CTRunGetGlyphCount(run) == 1 else { return nil }
            var glyph = [CGGlyph(0)]
            CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
            return Int(glyph[0])
        }
    }
#endif
