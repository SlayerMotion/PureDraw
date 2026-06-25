#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// Mark classes are local to each GPOS mark subtable: class 0 in one mark-to-base
    /// lookup is unrelated to class 0 in the next, and each pairs with its own
    /// BaseArray. Noto Nastaliq has eleven mark-to-base lookups and most base glyphs
    /// are covered by several of them, so merging every subtable into one map keyed
    /// by the raw class collides the classes and a base takes the wrong subtable's
    /// anchor. Each subtable's classes must occupy a disjoint range so the mark and
    /// base anchors stay paired.
    @Suite("GPOS mark classes do not collide across subtables")
    struct MarkClassNamespaceTests {
        private static let nastaliq = "/System/Library/Fonts/NotoNastaliq.ttc"

        @Test func belowDotAttachesBelowItsBase() throws {
            guard let data = FileManager.default.contents(atPath: Self.nastaliq),
                  let font = try? Font(data: [UInt8](data))
            else {
                return
            }
            // Glyph 16 is ThreeDotsDownBelowNS, a below mark; glyph 284 is BehxIni.A,
            // an initial beh that carries it. In the subtable that pairs them the mark
            // anchor is (0, -98) and the base anchor is (73, -264), so the mark sits at
            // (73, -166): below the base, the negative y a below dot must have. With
            // the class namespaces collided, the base's class-0 anchor came from a
            // different subtable and the dot landed above the baseline.
            let attachment = font.markAttachment()
            let offset = try #require(attachment.offset(base: 284, mark: 16), "the below dot must attach to its base")
            #expect(offset.x == 73, "dot x offset \(offset.x)")
            #expect(offset.y == -166, "the below dot must sit below the baseline, got y \(offset.y)")
        }

        @Test func markAttachmentTypeAndClassAreParsed() throws {
            guard let data = FileManager.default.contents(atPath: Self.nastaliq),
                  let font = try? Font(data: [UInt8](data))
            else {
                return
            }
            // Lookup 167 carries mark attachment type 2 (the high byte of its lookup
            // flag), so it steps over marks whose GDEF mark attachment class is not 2.
            // Noto Nastaliq's below dots are class 2 and its spacer is class 7, so the
            // lookup matches across the dots while skipping the spacer.
            let lookup = try #require(font.gsubLookup(at: 167))
            #expect(lookup.markAttachmentType == 2, "lookup 167 mark attachment type \(lookup.markAttachmentType)")
            #expect(font.markAttachmentClass(16) == 2, "the below dot is mark attachment class 2")
            #expect(font.markAttachmentClass(972) == 7, "the spacer is mark attachment class 7")
        }
    }
#endif
