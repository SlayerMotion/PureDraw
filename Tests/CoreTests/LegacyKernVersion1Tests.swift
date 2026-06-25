#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// The legacy `kern` table in the Apple AAT version 1.0 layout, which classic
    /// Apple fonts such as Helvetica carry (a u32 version and count, the subtable
    /// format in the coverage low byte) rather than the Microsoft version 0. Without
    /// reading it, Helvetica's pair kerning is lost and its spacing is wrong.
    @Suite("Legacy kern AAT version 1.0")
    struct LegacyKernVersion1Tests {
        @Test func helveticaVersion1KernIsRead() {
            let path = "/System/Library/Fonts/Helvetica.ttc"
            guard let data = FileManager.default.contents(atPath: path),
                  let font = try? Font(data: [UInt8](data))
            else {
                return
            }
            // Helvetica's kern is an AAT version 1.0 table; the map must be non-empty,
            // which only happens when the version-1 layout is parsed.
            let map = font.kerningMap()
            #expect(!map.adjustments.isEmpty, "Helvetica's AAT version 1.0 kern must be read")

            // A known kerning pair: capital T followed by a lowercase vowel tucks the
            // vowel under the bar. Find it through the cmap and assert a negative kern.
            if let upperT = font.glyphIndex(for: "T"), let lowerO = font.glyphIndex(for: "o") {
                let value = map.adjustment(firstGlyph: upperT, secondGlyph: lowerO)
                #expect(value < 0, "T o should kern negative, got \(value)")
            }

            // Excluding the legacy table yields no kerning, confirming the kerning
            // comes from the legacy table and the opt-out works.
            let withoutLegacy = font.kerningMap(includeLegacyKern: false)
            #expect(withoutLegacy.adjustments.isEmpty, "Helvetica has no GPOS kerning, only legacy")
        }
    }
#endif
