#if canImport(CoreText)
    @testable import Core
    import CoreGraphics
    import CoreText
    import Foundation
    import Testing

    /// A differential trip (the Knuth oracle check) for the GPOS and kern parsing:
    /// shape letter pairs through Core Text on a real system font and assert that
    /// PureDraw's parsed kerning matches Apple's own shaper. Skipped (returns) when
    /// no suitable font is present, so the suite stays portable; the assertion that
    /// at least one kerned pair was compared keeps it from passing vacuously.
    @Suite("Kerning matches Core Text (PureDraw#140 oracle trip)")
    struct KerningCoreTextTests {
        @Test func kerningMatchesCoreTextOnSystemFont() throws {
            let candidates = [
                "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
                "/System/Library/Fonts/Supplemental/Georgia.ttf",
                "/System/Library/Fonts/Supplemental/Arial.ttf",
                "/System/Library/Fonts/Supplemental/Verdana.ttf",
            ]
            guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
                  let data = FileManager.default.contents(atPath: path)
            else {
                return
            }
            let font = try Font(data: [UInt8](data))
            let kerning = font.kerningMap()
            // The chosen font (a standard text face) is known to kern, so an empty
            // map would mean the parser missed it, not that the trip is vacuous.
            #expect(!kerning.isEmpty, "expected \(path) to carry kerning")
            let unitsPerEm = Double(font.unitsPerEm)

            guard let provider = CGDataProvider(data: data as CFData),
                  let cgFont = CGFont(provider)
            else {
                return
            }
            // Size equal to units-per-em makes Core Text positions and advances read
            // directly in font units (scale 1).
            let ctFont = CTFontCreateWithGraphicsFont(cgFont, CGFloat(unitsPerEm), nil, nil)

            let letters = Array("AVWTYLPFJoarvwyc.,-")
            var comparedKernedPairs = 0
            for first in letters {
                for second in letters {
                    guard let result = coreTextKern(String([first, second]), font: ctFont) else { continue }
                    let mine = kerning.adjustment(firstGlyph: result.firstGlyph, secondGlyph: result.secondGlyph)
                    #expect(
                        abs(result.kern - mine) <= 2.0,
                        "pair \(first)\(second): Core Text \(result.kern) vs PureDraw \(mine)"
                    )
                    if abs(result.kern) > 0.5 || mine != 0 {
                        comparedKernedPairs += 1
                    }
                }
            }
            #expect(comparedKernedPairs > 0, "the trip must exercise at least one kerned pair")
        }

        private struct PairKern {
            let firstGlyph: Int
            let secondGlyph: Int
            let kern: Double
        }

        /// Shapes a two-character string through Core Text and returns the kerning it
        /// applied between the two glyphs, or `nil` if the pair did not shape into a
        /// single run of exactly two glyphs (a ligature or reordering).
        private func coreTextKern(_ pair: String, font ctFont: CTFont) -> PairKern? {
            let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
            let attributed = NSAttributedString(string: pair, attributes: [fontKey: ctFont])
            let line = CTLineCreateWithAttributedString(attributed)
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], runs.count == 1 else { return nil }
            let run = runs[0]
            guard CTRunGetGlyphCount(run) == 2 else { return nil }

            var glyphs = [CGGlyph](repeating: 0, count: 2)
            var positions = [CGPoint](repeating: .zero, count: 2)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 2), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 2), &positions)

            var firstGlyph = [glyphs[0]]
            var advance = [CGSize.zero]
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &firstGlyph, &advance, 1)

            let kern = Double(positions[1].x - positions[0].x) - Double(advance[0].width)
            return PairKern(firstGlyph: Int(glyphs[0]), secondGlyph: Int(glyphs[1]), kern: kern)
        }
    }
#endif
