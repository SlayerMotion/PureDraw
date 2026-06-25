#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// A GSUB lookup whose flag carries UseMarkFilteringSet (0x10) skips every mark
    /// not in a named GDEF mark glyph set, distinct from IgnoreMarks (which skips
    /// all marks). SF Hebrew composes shin and its dot with a ccmp ligature lookup
    /// that uses a filtering set containing the dot but not the vowel points, so the
    /// composition matches across a hiriq between them. The lookup must expose its
    /// filtering-set index, and set membership must distinguish the dot from the
    /// vowel.
    @Suite("GDEF mark filtering sets (UseMarkFilteringSet)")
    struct MarkFilteringSetTests {
        private static let sfHebrew = "/System/Library/Fonts/SFHebrew.ttf"

        @Test func ccmpLookupCarriesFilteringSetThatKeepsTheDotNotTheVowel() throws {
            guard let data = FileManager.default.contents(atPath: Self.sfHebrew),
                  let font = try? Font(data: [UInt8](data))
            else {
                return
            }
            // Lookup 1 is the shin + shin-dot ccmp ligature, flag UseMarkFilteringSet.
            let lookup = try #require(font.gsubLookup(at: 1))
            let set = try #require(lookup.markFilteringSet, "the ccmp lookup must carry a mark filtering set")
            #expect(!lookup.ignoreMarks, "UseMarkFilteringSet is not IgnoreMarks: it must not skip every mark")
            #expect(font.markFilterSetContains(set: set, glyph: 109), "the shin dot (109) must be in the filtering set, so it is matched")
            #expect(!font.markFilterSetContains(set: set, glyph: 148), "the hiriq (148) must not be in the set, so it is skipped")
        }
    }
#endif
