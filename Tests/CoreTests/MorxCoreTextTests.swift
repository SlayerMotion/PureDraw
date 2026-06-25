#if canImport(CoreText)
    @testable import Core
    import CoreGraphics
    import CoreText
    import Foundation
    import Testing

    /// The differential trip for the AAT `morx` engine: shape Khmer clusters through
    /// PureDraw's `morx` chain and through Core Text on the same Apple font, and
    /// require the glyph sequences agree. Core Text shapes this font through `morx`
    /// rather than OpenType GSUB, so this proves PureDraw drives the same state
    /// machines: ligature (coeng subscripts), insertion and rearrangement (split-vowel
    /// pre-base pieces), and contextual and non-contextual substitution.
    @Suite("AAT morx shaping matches Core Text")
    struct MorxCoreTextTests {
        private static let fontPath = "/System/Library/Fonts/Supplemental/Khmer Sangam MN.ttf"

        private func glyphSequences(_ scalars: [UInt32]) throws -> (mine: [Int], theirs: [Int])? {
            guard let data = FileManager.default.contents(atPath: Self.fontPath),
                  let font = try? Font(data: [UInt8](data)),
                  let provider = CGDataProvider(data: data as CFData),
                  let cgFont = CGFont(provider)
            else {
                return nil
            }
            let input = try scalars.enumerated().map { offset, value -> MorxGlyph in
                let scalar = try #require(Unicode.Scalar(value))
                return MorxGlyph(glyphID: font.glyphIndex(for: scalar) ?? 0, cluster: offset)
            }
            let mine = font.applyMorx(input).map(\.glyphID)

            let ctFont = CTFontCreateWithGraphicsFont(cgFont, CGFloat(font.unitsPerEm), nil, nil)
            let key = NSAttributedString.Key(kCTFontAttributeName as String)
            let string = String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar($0) }))
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [key: ctFont]))
            var theirs: [Int] = []
            for run in (CTLineGetGlyphRuns(ctLine) as? [CTRun]) ?? [] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                theirs.append(contentsOf: glyphs.map(Int.init))
            }
            return (mine, theirs)
        }

        @Test(arguments: [
            [0x1780] as [UInt32], // ka, identity
            [0x1780, 0x17D2, 0x1780], // coeng subscript (ligature)
            [0x1780, 0x17D2, 0x179A], // coeng-ro (ligature + rearrangement)
            [0x1780, 0x17C1], // pre-base vowel (rearrangement)
            [0x1780, 0x17BE], // split vowel oe (insertion + rearrangement)
            [0x1780, 0x17C4], // split vowel oo (insertion + rearrangement + ligature)
            [0x1780, 0x17C5], // split vowel au
            [0x1780, 0x17D2, 0x1780, 0x17C4], // split vowel over a subscript stack
        ])
        func morxMatchesCoreText(_ scalars: [UInt32]) throws {
            guard let (mine, theirs) = try glyphSequences(scalars) else { return }
            #expect(mine == theirs, "morx \(scalars.map { String($0, radix: 16) }): PureDraw \(mine) vs Core Text \(theirs)")
            #expect(!mine.isEmpty)
        }
    }
#endif
