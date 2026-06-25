/// A glyph passing through the AAT `morx` metamorphosis engine: its glyph id and
/// the index of the input glyph it derives from, so the shaping tier can keep
/// cluster and selection information across reordering, ligature, and insertion.
///
/// `morx` (the extended glyph metamorphosis table, Apple TrueType Reference
/// Manual) transforms a glyph sequence the way OpenType GSUB does, but through
/// chained finite state machines rather than feature lookups. Core Text prefers
/// `morx` over GSUB when a font carries both, which Apple system fonts for complex
/// scripts (Khmer, for one) do, so reproducing Core Text's shaping for those fonts
/// means driving their `morx` chain.
public struct MorxGlyph: Equatable, Sendable {
    /// The glyph index.
    public let glyphID: Int
    /// The input glyph index this glyph derives from. A ligature inherits the
    /// earliest component's index; an inserted glyph takes the index of the glyph
    /// it was inserted next to; a reordered glyph keeps its own.
    public let cluster: Int

    public init(glyphID: Int, cluster: Int) {
        self.glyphID = glyphID
        self.cluster = cluster
    }
}
