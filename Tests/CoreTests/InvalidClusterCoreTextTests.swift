#if canImport(CoreText)
    @testable import Core
    import CoreGraphics
    import CoreText
    import Foundation
    import Testing

    /// Malformed-cluster robustness: a dependent sign with no base (a lone matra, a
    /// lone virama or coeng, a doubled vowel sign) is invalid, and how it renders is
    /// the font's `morx` choice, not the shaper's. Because PureDraw runs the font's
    /// own `morx`, it reproduces Core Text's rendering of these exactly, including
    /// whichever fallback the font applies. This pins that the engine does not diverge
    /// on input outside the well-formed grammar (the boundary case Knuth would insist
    /// on enumerating).
    @Suite("AAT morx invalid-cluster rendering matches Core Text")
    struct InvalidClusterCoreTextTests {
        @Test(arguments: [
            ("Devanagari Sangam MN.ttc", [0x093F] as [UInt32]), // lone i-matra
            ("Devanagari Sangam MN.ttc", [0x094D]), // lone virama
            ("Devanagari Sangam MN.ttc", [0x0902]), // lone anusvara
            ("Devanagari Sangam MN.ttc", [0x0915, 0x093F, 0x093F]), // doubled i-matra
            ("Bangla MN.ttc", [0x09BF]), // lone i-matra
            ("Bangla MN.ttc", [0x09CD]), // lone virama
            ("Tamil MN.ttc", [0x0BBF]), // lone vowel sign
            ("Khmer Sangam MN.ttf", [0x17D2]), // lone coeng
            ("Khmer Sangam MN.ttf", [0x17C1]), // lone pre-base vowel
            ("Myanmar MN.ttc", [0x103B]), // lone medial
            ("Myanmar MN.ttc", [0x1039]), // lone virama
        ])
        func invalidClusterMatchesCoreText(_ file: String, _ scalars: [UInt32]) throws {
            let path = "/System/Library/Fonts/Supplemental/\(file)"
            guard let data = FileManager.default.contents(atPath: path),
                  let font = try? Font(data: [UInt8](data)),
                  let provider = CGDataProvider(data: data as CFData),
                  let cgFont = CGFont(provider)
            else {
                return
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
            #expect(mine == theirs, "\(file) \(scalars.map { String($0, radix: 16) }): PureDraw \(mine) vs Core Text \(theirs)")
        }
    }
#endif
