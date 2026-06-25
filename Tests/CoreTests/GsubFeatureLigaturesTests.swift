#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// The per-feature ligature accessor surfaces GSUB ligatures (lookup type 4) that
    /// live under a feature tag the broad ``Font/ligatures(restrictTo:)`` does not
    /// gather. The motivating case is the Khmer below-base feature `blwf`, whose coeng
    /// (U+17D2) + consonant ligatures form the subscript consonants. The broad
    /// accessor gathers only `liga`/`rlig`/`ccmp`, so without the per-tag accessor the
    /// Khmer subscript conjuncts are invisible to the shaper.
    @Suite("GSUB per-feature ligatures (ligatures(feature:))")
    struct GsubFeatureLigaturesTests {
        private static let khmerFont = "/System/Library/Fonts/Supplemental/Khmer Sangam MN.ttf"

        @Test func blwfSurfacesKhmerCoengSubscriptLigatures() throws {
            guard let data = FileManager.default.contents(atPath: Self.khmerFont),
                  let font = try? Font(data: [UInt8](data)),
                  let coeng = try font.glyphIndex(for: #require(Unicode.Scalar(0x17D2))),
                  let ka = try font.glyphIndex(for: #require(Unicode.Scalar(0x1780)))
            else {
                return
            }
            let blwf = font.ligatures(feature: "blwf")
            // The coeng + ka subscript conjunct must be present: a two-component
            // ligature whose components are exactly the coeng and the consonant.
            let coengKa = blwf.first { $0.components == [coeng, ka] }
            #expect(coengKa != nil, "blwf must carry the coeng + ka subscript ligature")
            #expect(coengKa.map { $0.ligatureGlyph != ka && $0.ligatureGlyph != coeng } ?? false, "the subscript must be a distinct glyph")
            // Non-vacuity: the font defines a whole family of coeng + consonant
            // subscripts, all beginning with the coeng glyph.
            let coengLed = blwf.filter { $0.components.first == coeng && $0.components.count == 2 }
            #expect(coengLed.count >= 20, "blwf must carry the full set of coeng subscript conjuncts, found \(coengLed.count)")

            // The broad ligatures() accessor, gathering only liga/rlig/ccmp, does not
            // see these: the per-feature accessor is what surfaces them.
            #expect(font.ligatures().contains { $0.components == [coeng, ka] } == false, "the broad accessor must not gather blwf ligatures")
        }
    }
#endif
