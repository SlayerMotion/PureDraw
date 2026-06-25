/// GPOS mark-to-base attachment (lookup type 4): the anchor data that seats a
/// combining mark over its base glyph, for example an Arabic vowel mark over its
/// letter. This is the typed boundary the shaping tier consumes: PureDraw parses
/// the GPOS table, this value answers where a mark sits relative to its base.
/// Coordinates are in font units.
public struct MarkAttachment: Equatable, Sendable {
    /// A point in the glyph's design space, in font units.
    public struct Point: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    /// A mark glyph's class and the anchor on the mark that aligns with the base.
    public struct Mark: Equatable, Sendable {
        public let markClass: Int
        public let anchor: Point
        public init(markClass: Int, anchor: Point) {
            self.markClass = markClass
            self.anchor = anchor
        }
    }

    /// Each mark glyph to its class-and-anchor records. A glyph carries more than one
    /// when it is a mark in several mark-to-base subtables, each pairing it with a
    /// different base set under a different class: a Devanagari reph is class 0 against
    /// the wide base it sits inside in one subtable and a different class against other
    /// bases in another. Flattening to one record would drop every pairing but the last
    /// and orphan the mark from the base whose anchor it should use. The records are in
    /// subtable (lookup) order, so the first that a base offers an anchor for wins, the
    /// order Core Text resolves them in.
    public let marks: [Int: [Mark]]
    /// Each base glyph to the anchor it offers for each mark class.
    public let bases: [Int: [Int: Point]]

    public init(marks: [Int: [Mark]], bases: [Int: [Int: Point]]) {
        self.marks = marks
        self.bases = bases
    }

    /// Whether the font carries no mark attachment.
    public var isEmpty: Bool {
        marks.isEmpty || bases.isEmpty
    }

    /// Whether `glyph` is a mark that attaches to a base.
    public func isMark(_ glyph: Int) -> Bool {
        marks[glyph] != nil
    }

    /// The offset, in font units, to place `mark`'s glyph relative to the origin
    /// of `base`'s glyph so their anchors coincide, or `nil` if the pair does not
    /// attach (the mark is unknown, or no class the mark carries is one the base
    /// offers an anchor for). When the mark has records in several subtables, the
    /// first, in lookup order, whose class the base anchors wins.
    public func offset(base: Int, mark: Int) -> Point? {
        guard let records = marks[mark], let baseAnchors = bases[base] else { return nil }
        for record in records {
            if let basePoint = baseAnchors[record.markClass] {
                return Point(x: basePoint.x - record.anchor.x, y: basePoint.y - record.anchor.y)
            }
        }
        return nil
    }
}
