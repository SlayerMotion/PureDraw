#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// The AAT `kerx` pair-kerning formats other than the anchor attachment: format 0
    /// (an ordered list of glyph pairs) and format 2 (class pairs). The Apple Kannada
    /// and Malayalam fonts carry format-0 subtables that pull specific consonant and
    /// vowel-sign pairs together; without them the spacing of those pairs is wrong by
    /// the kerning amount. This verifies PureDraw reads the format-0 values so the
    /// shaping tier reproduces Core Text's spacing.
    @Suite("AAT kerx pair kerning (format 0)")
    struct KerxKerningTests {
        @Test func kannadaFormat0PairKerning() throws {
            let path = "/System/Library/Fonts/Supplemental/Kannada MN.ttc"
            guard let data = FileManager.default.contents(atPath: path),
                  let font = try? Font(data: [UInt8](data))
            else {
                return
            }
            // Glyph 138 is gha, 176 is the uu vowel sign; the font kerns that pair by
            // -216 font units (a documented format-0 entry).
            let adjustments = font.kerxHorizontalAdjustments([138, 176])
            #expect(adjustments.count == 2)
            #expect(adjustments[0] == 0, "the first glyph has no preceding kern")
            #expect(adjustments[1] == -216, "gha + uu kerns by -216, got \(adjustments[1])")

            // A pair the font does not kern returns zero, so the kerning is specific,
            // not a blanket shift.
            let none = font.kerxHorizontalAdjustments([138, 138])
            #expect(none == [0, 0], "an unkerned pair must not be shifted, got \(none)")
        }
    }
#endif
