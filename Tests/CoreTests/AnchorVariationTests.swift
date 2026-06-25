#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// GPOS mark anchors vary with the axes. A variable font stores its mark-to-base
    /// anchors as Anchor format 3 whose x and y device tables are VariationIndex
    /// tables into the GDEF ItemVariationStore; at a non-default instance the anchor
    /// shifts by the interpolated delta, so a dot stays on its letter as the weight
    /// changes. SF Arabic exercises this. Without applying the VariationIndex the
    /// anchor would be frozen at its default and the mark would drift at other
    /// weights.
    @Suite("GPOS anchors vary with the variation instance")
    struct AnchorVariationTests {
        private static let sfArabic = "/System/Library/Fonts/SFArabic.ttf"

        @Test func markAnchorsShiftWithWeight() {
            guard let data = FileManager.default.contents(atPath: Self.sfArabic),
                  let font = try? Font(data: [UInt8](data)), font.isVariable
            else {
                return
            }
            let defaultMarks = font.markAttachment()
            let heavyMarks = font.markAttachment(variations: ["wght": 900])
            #expect(!defaultMarks.isEmpty, "SF Arabic must carry mark attachment")
            // Some base offers a base anchor that differs between the default and the
            // heaviest weight: the VariationIndex delta is applied.
            var shifted = false
            for (base, classes) in defaultMarks.bases {
                for (markClass, point) in classes {
                    if let heavy = heavyMarks.bases[base]?[markClass], heavy != point {
                        shifted = true
                        break
                    }
                }
                if shifted { break }
            }
            #expect(shifted, "a mark anchor must shift between the default weight and wght 900")
        }
    }
#endif
