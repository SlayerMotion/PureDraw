#if canImport(CoreText)
    import Core
    import CoreGraphics
    import CoreText
    import Foundation
    import Testing

    /// Vertical advance parsing (vhea/vmtx) verified against CoreText: for a real
    /// CJK font with vertical metrics, `Font.advanceHeight(forGlyph:)` must match
    /// `CTFontGetAdvancesForGlyphs(.vertical)` glyph for glyph. A font without
    /// vertical metrics must report zero, the caller's signal to synthesize.
    struct VerticalMetricsCoreTextTests {
        private let verticalFontPath = "/System/Library/Fonts/Supplemental/AppleMyungjo.ttf"
        private let horizontalFontPath = "/System/Library/Fonts/Supplemental/Times New Roman.ttf"

        @Test func advanceHeightMatchesCoreText() throws {
            guard let data = FileManager.default.contents(atPath: verticalFontPath),
                  let provider = CGDataProvider(data: data as CFData),
                  let cgFont = CGFont(provider)
            else {
                return
            }
            let font = try Font(data: [UInt8](data))
            let upm = CGFloat(font.unitsPerEm)
            let ctFont = CTFontCreateWithGraphicsFont(cgFont, upm, nil, nil)

            // A spread of CJK and punctuation scalars that carry vertical metrics.
            let samples = "\u{AC00}\u{D55C}\u{AE00}\u{4E2D}\u{6587}\u{3002}\u{FF0C}\u{30A2}"
            var compared = 0
            for scalar in samples.unicodeScalars {
                var utf16 = Array(String(scalar).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
                guard CTFontGetGlyphsForCharacters(ctFont, &utf16, &glyphs, utf16.count), glyphs[0] != 0 else { continue }
                var ids = [glyphs[0]]
                var advances = [CGSize.zero]
                CTFontGetAdvancesForGlyphs(ctFont, .vertical, &ids, &advances, 1)
                // CoreText returns the advance scalar in the width field for both
                // orientations; with .vertical that scalar is the vmtx advance
                // height, in font units at upm size.
                let theirs = abs(Double(advances[0].width))
                let mine = font.advanceHeight(forGlyph: Int(glyphs[0]))
                #expect(mine > 0, "glyph \(glyphs[0]) should have a vertical advance")
                #expect(abs(mine - theirs) <= 1.0, "glyph \(glyphs[0]): PureDraw \(mine) vs CoreText \(theirs)")
                compared += 1
            }
            #expect(compared > 0, "the trip must compare at least one vertical advance against CoreText")
        }

        @Test func horizontalOnlyFontReportsNoVerticalAdvance() throws {
            guard let data = FileManager.default.contents(atPath: horizontalFontPath) else { return }
            let font = try Font(data: [UInt8](data))
            // Times New Roman carries no vmtx; every glyph's advance height is zero.
            #expect(font.advanceHeight(forGlyph: 36) == 0)
            #expect(font.advanceHeight(forGlyph: 1) == 0)
        }
    }
#endif
