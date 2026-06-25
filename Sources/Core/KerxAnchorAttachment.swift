/// An AAT `kerx` format-4 anchor attachment: the engine found that the glyph at
/// `currentIndex` should attach to the glyph at `markedIndex` by aligning an anchor
/// point on each. The anchors, in font units from each glyph's origin, are resolved
/// from the font's `ankr` table. The shaping tier computes the placement shift from
/// these and the glyphs' pen positions, so the attachment math stays where the pen
/// positions live.
///
/// This is the AAT counterpart to GPOS mark-to-base attachment, the mechanism Core
/// Text uses to seat, for example, a Myanmar subscript under its base.
public struct KerxAnchorAttachment: Equatable, Sendable {
    /// Index of the glyph being positioned, in the run passed to the reader.
    public let currentIndex: Int
    /// Index of the glyph it attaches to (the marked glyph).
    public let markedIndex: Int
    /// The marked glyph's anchor point, font units from its origin.
    public let markedAnchorX: Int
    public let markedAnchorY: Int
    /// The current glyph's anchor point, font units from its origin.
    public let currentAnchorX: Int
    public let currentAnchorY: Int

    public init(currentIndex: Int, markedIndex: Int, markedAnchorX: Int, markedAnchorY: Int, currentAnchorX: Int, currentAnchorY: Int) {
        self.currentIndex = currentIndex
        self.markedIndex = markedIndex
        self.markedAnchorX = markedAnchorX
        self.markedAnchorY = markedAnchorY
        self.currentAnchorX = currentAnchorX
        self.currentAnchorY = currentAnchorY
    }
}
