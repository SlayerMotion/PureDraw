/// GPOS mark-to-ligature attachment (lookup type 5): the anchor data that seats a
/// combining mark over a specific component of a ligature glyph, for example a
/// vowel mark over the correct part of an Arabic lam-alef. It is the ligature
/// analogue of ``MarkAttachment``: a ligature offers, per component, an anchor for
/// each mark class, and the shaping tier chooses the component a mark belongs to.
/// This is the typed boundary the shaping tier consumes: PureDraw parses the GPOS
/// table, this value answers where a mark sits relative to a ligature component.
/// Coordinates are in font units.
public struct MarkLigatureAttachment: Equatable, Sendable {
    /// Each mark glyph to its class and the anchor on the mark that aligns with the
    /// ligature component (reusing ``MarkAttachment/Mark``).
    public let marks: [Int: MarkAttachment.Mark]
    /// Each ligature glyph to its components, in order; each component offers an
    /// anchor (``MarkAttachment/Point``) per mark class. A component that anchors no
    /// class, or a class a component does not anchor, is simply absent.
    public let ligatures: [Int: [[Int: MarkAttachment.Point]]]

    public init(marks: [Int: MarkAttachment.Mark], ligatures: [Int: [[Int: MarkAttachment.Point]]]) {
        self.marks = marks
        self.ligatures = ligatures
    }

    /// Whether the font carries no mark-to-ligature attachment.
    public var isEmpty: Bool {
        marks.isEmpty || ligatures.isEmpty
    }

    /// Whether `glyph` is a mark that attaches to a ligature component.
    public func isMark(_ glyph: Int) -> Bool {
        marks[glyph] != nil
    }

    /// The offset, in font units, to place `mark`'s glyph relative to the origin of
    /// `ligature`'s glyph so their anchors coincide on `component`, or `nil` when
    /// the mark is unknown, the component is out of range, or that component offers
    /// no anchor for the mark's class.
    public func offset(ligature: Int, component: Int, mark: Int) -> MarkAttachment.Point? {
        guard let mark = marks[mark],
              let components = ligatures[ligature],
              component >= 0, component < components.count,
              let anchor = components[component][mark.markClass]
        else {
            return nil
        }
        return MarkAttachment.Point(x: anchor.x - mark.anchor.x, y: anchor.y - mark.anchor.y)
    }
}
