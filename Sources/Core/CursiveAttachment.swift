/// GPOS cursive attachment (lookup type 3): the entry and exit anchors that join
/// glyphs along a flowing baseline, so a connected script (nastaliq Urdu, for
/// example) links one glyph's exit to the next glyph's entry. This is the typed
/// boundary the shaping tier consumes: PureDraw parses the GPOS table, this value
/// answers where a glyph connects. Coordinates are in font units.
public struct CursiveAttachment: Equatable, Sendable {
    /// A point in the glyph's design space, in font units.
    public struct Point: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    /// Each glyph's entry anchor: where the preceding glyph's exit connects to it.
    public let entries: [Int: Point]
    /// Each glyph's exit anchor: where it connects to the following glyph's entry.
    public let exits: [Int: Point]

    public init(entries: [Int: Point], exits: [Int: Point]) {
        self.entries = entries
        self.exits = exits
    }

    /// Whether the font carries no cursive attachment.
    public var isEmpty: Bool {
        entries.isEmpty && exits.isEmpty
    }

    /// The entry anchor of `glyph`, where a preceding glyph's exit meets it, or
    /// `nil` if the glyph has none.
    public func entry(_ glyph: Int) -> Point? {
        entries[glyph]
    }

    /// The exit anchor of `glyph`, where it meets a following glyph's entry, or
    /// `nil` if the glyph has none.
    public func exit(_ glyph: Int) -> Point? {
        exits[glyph]
    }
}
