#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// GPOS contextual positioning (lookup types 7 and 8) is parsed across all three
    /// formats, not only format 3. Noto Nastaliq carries the per-letter advances of
    /// its diagonal baseline in a type-7 format-2 (class-based) contextual lookup
    /// under the `curs` feature, which selects a single-adjustment lookup per glyph
    /// from context. The format-3-only parser saw none of these, so the advances
    /// were dropped and connected words drifted; the format-1/2 parsing must surface
    /// them.
    @Suite("GPOS contextual positioning formats 1 and 2")
    struct ContextualPositioningFormatTests {
        private static let nastaliq = "/System/Library/Fonts/NotoNastaliq.ttc"

        @Test func cursContextualAdvancesAreParsedFromFormat2() {
            guard let data = FileManager.default.contents(atPath: Self.nastaliq),
                  let font = try? Font(data: [UInt8](data))
            else {
                return
            }
            let rules = font.contextualPositioning(feature: "curs")
            #expect(!rules.isEmpty, "the curs feature's type-7 format-2 contextual positioning must parse")
            // Glyph 329 (BehxIni.outD2Y) takes a context-selected advance: its hmtx
            // advance is 204, and the contextual rules add an extra advance (the
            // first such lookup is +61). At least one rule must carry an advance
            // adjustment for it.
            let adjusts329 = rules.contains { rule in
                rule.actions.contains { $0.adjustments[329]?.xAdvance ?? 0 != 0 }
            }
            #expect(adjusts329, "a curs contextual rule must adjust glyph 329's advance")
        }
    }
#endif
