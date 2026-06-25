#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// The AAT `kerx` format-4 anchor attachment and the `ankr` table it reads from.
    /// On the Apple Myanmar font, a virama-subjoined consonant attaches to its base by
    /// aligning anchor points; the resulting horizontal shift is what pulls the
    /// subscript under the base. This verifies PureDraw resolves the attachment and
    /// its anchors so the shaping tier can reproduce Core Text's positioning.
    @Suite("AAT kerx anchor attachment (kerx format 4 + ankr)")
    struct KerxAnchorTests {
        private static let fontPath = "/System/Library/Fonts/Supplemental/Myanmar MN.ttc"

        @Test func subscriptAttachesToBaseByAnchor() throws {
            guard let data = FileManager.default.contents(atPath: Self.fontPath),
                  let font = try? Font(data: [UInt8](data)),
                  let ka = try font.glyphIndex(for: #require(Unicode.Scalar(0x1000)))
            else {
                return
            }
            // Shape ka + virama + ka through morx to get the base and the subscript.
            let input = [0x1000, 0x1039, 0x1000].enumerated().compactMap { offset, value -> MorxGlyph? in
                guard let scalar = Unicode.Scalar(value) else { return nil }
                return MorxGlyph(glyphID: font.glyphIndex(for: scalar) ?? 0, cluster: offset)
            }
            let shaped = font.applyMorx(input).map(\.glyphID)
            #expect(shaped.count == 2, "ka + virama + ka collapses to a base and a subscript")
            #expect(shaped.first == ka)
            let subscriptGlyph = shaped[1]

            // The subscript attaches to the base by anchor alignment.
            let attachments = font.kerxAnchorAttachments(shaped)
            let attach = try #require(attachments.first { $0.currentIndex == 1 && $0.markedIndex == 0 }, "the subscript must anchor-attach to the base")

            // The shift that places the subscript: pen[base]=0, pen[subscript]=advance(base).
            let baseAdvance = font.advanceWidth(forGlyph: ka)
            let dx = Double(attach.markedAnchorX) - baseAdvance - Double(attach.currentAnchorX)
            // Non-vacuity: the attachment actually moves the subscript (it is not a
            // zero shift), pulling it back under the base.
            #expect(dx != 0, "the anchor attachment must shift the subscript")
            #expect(dx < 0, "the subscript is pulled left, under the base, shift \(dx)")
            #expect(attach.markedAnchorY == attach.currentAnchorY, "this conjunct aligns on the baseline")
            #expect(subscriptGlyph != ka)
        }
    }
#endif
