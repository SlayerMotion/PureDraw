#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// GPOS pair kern values vary with the axes. A variable font stores the kern in
    /// a ValueRecord whose XAdvance carries an XAdvDevice that is a VariationIndex
    /// into the GDEF ItemVariationStore; at a non-default instance the kern changes
    /// by the interpolated delta. SF Hebrew exercises this (ValueFormat 0x44,
    /// XAdvance plus XAdvDevice). Without applying the VariationIndex the kern would
    /// be frozen at its default and pointed text would drift at other weights.
    @Suite("GPOS pair kern varies with the variation instance")
    struct KernVariationTests {
        private static let sfHebrew = "/System/Library/Fonts/SFHebrew.ttf"

        @Test func pairKernShiftsWithWeight() {
            guard let data = FileManager.default.contents(atPath: Self.sfHebrew),
                  let font = try? Font(data: [UInt8](data)), font.isVariable
            else {
                return
            }
            let defaultKern = font.kerningMap(includeLegacyKern: false)
            let heavyKern = font.kerningMap(includeLegacyKern: false, variations: ["wght": 900])
            #expect(!defaultKern.isEmpty, "SF Hebrew must carry GPOS pair kern")
            // The resh-heh pair (glyphs 50, 12) kerns -85 at the default weight and a
            // different amount at the heaviest, the VariationIndex delta applied.
            let defaultValue = defaultKern.adjustment(firstGlyph: 50, secondGlyph: 12)
            let heavyValue = heavyKern.adjustment(firstGlyph: 50, secondGlyph: 12)
            #expect(defaultValue != 0, "the resh-heh pair must kern at the default weight, got \(defaultValue)")
            #expect(defaultValue != heavyValue, "the kern must change between the default weight and wght 900, both \(defaultValue)")
        }
    }
#endif
