#if canImport(CoreText)
    @testable import Core
    import CoreGraphics
    import CoreText
    import Foundation
    import Testing

    /// The differential trip for the AAT `trak` table: Apple's optical fonts carry a
    /// tracking table that Core Text bakes into `CTFontGetAdvancesForGlyphs`, tightening
    /// advances at large sizes and loosening them at small ones. PureDraw parses the
    /// normal (`0.0`) track and reports the per-size tracking; this verifies it against
    /// Core Text by isolating the constant Core Text adds to each glyph's advance.
    ///
    /// Verified on New York, an optical-size system serif with a `trak` table. Skipped
    /// when the font is absent so the suite stays portable; non-vacuity is pinned by
    /// requiring the table to be present and the tracking to actually vary with size.
    @Suite("PureDraw trak tracking matches Core Text")
    struct TrackingCoreTextTests {
        private static let path = "/System/Library/Fonts/NewYork.ttf"

        @Test func trackingMatchesCoreTextAcrossSizes() throws {
            guard let data = FileManager.default.contents(atPath: Self.path),
                  let program = try? Font(data: [UInt8](data)),
                  let provider = CGDataProvider(data: data as CFData),
                  let cgFont = CGFont(provider)
            else {
                return
            }
            // A trak table must be present, else the trip is vacuous.
            #expect(program.horizontalTracking(forPointSize: 256) != 0)
            let upm = Double(program.unitsPerEm)
            let glyph = try #require(program.glyphIndex(for: "H"))
            let opsz = program.variationAxes.first(where: { $0.tag == "opsz" })
            // Sizes that fall on and between the trak size rows. Each is small enough
            // that reconstructing font units from the point advance does not amplify
            // Core Text's device-grid rounding into the comparison.
            for size in [8.0, 12.0, 24.0, 36.0, 48.0] {
                // Core Text's advance at this size, in font units, includes tracking.
                let ctFont = CTFontCreateWithGraphicsFont(cgFont, CGFloat(size), nil, nil)
                var cgGlyph = CGGlyph(glyph)
                var advance = CGSize.zero
                CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &cgGlyph, &advance, 1)
                let ctUnits = advance.width * upm / size
                // PureDraw's instance advance at the optical size Core Text drives from
                // the point size, plus the tracking PureDraw reports for that size.
                let opszValue = opsz.map { min(max(size, $0.minValue), $0.maxValue) }
                let instance = opszValue.map { program.advanceWidth(forGlyph: glyph, variations: ["opsz": $0]) }
                    ?? program.advanceWidth(forGlyph: glyph)
                let mine = instance + program.horizontalTracking(forPointSize: size)
                #expect(abs(mine - ctUnits) <= 0.5, "size \(size): PureDraw \(mine) vs Core Text \(ctUnits)")
            }
            // Non-vacuity: tracking is loose (positive) at small sizes and tight
            // (negative) at large ones, so it provably varies with size.
            #expect(program.horizontalTracking(forPointSize: 8) > 0)
            #expect(program.horizontalTracking(forPointSize: 256) < 0)
        }

        @Test func absentTableTracksZero() {
            // SF Arabic carries no trak table; tracking must be zero at every size.
            guard let data = FileManager.default.contents(atPath: "/System/Library/Fonts/SFArabic.ttf"),
                  let program = try? Font(data: [UInt8](data))
            else {
                return
            }
            #expect(program.horizontalTracking(forPointSize: 12) == 0)
            #expect(program.horizontalTracking(forPointSize: 96) == 0)
        }
    }
#endif
