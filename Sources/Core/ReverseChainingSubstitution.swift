/// A GSUB reverse chaining contextual single substitution rule (lookup type 8): a
/// covered glyph is replaced by a fixed substitute when its backtrack and
/// lookahead neighbours match, and the rule is applied to a run from the end
/// toward the start (the only GSUB lookup processed in reverse). The substitution
/// is direct, a glyph-to-glyph `mapping` rather than a nested lookup, which is why
/// reverse chaining carries its substitutes inline. This is the typed boundary the
/// shaping tier consumes: PureDraw parses the GSUB table, this value answers
/// whether a position matches and what it becomes.
///
/// Bounded to format 1 (each context position is a coverage set), the only format
/// the lookup defines.
public struct ReverseChainingSubstitution: Equatable, Sendable {
    /// The glyphs that must precede the input, ordered from the one nearest the
    /// input outward (the OpenType backtrack order).
    public let backtrack: [Set<Int>]
    /// The glyphs that must follow the input, in text order.
    public let lookahead: [Set<Int>]
    /// The input glyph to its substitute (coverage glyph i maps to substitute i).
    public let mapping: [Int: Int]
    /// Whether the lookup skips mark glyphs when matching the context (the
    /// `IgnoreMarks` or `UseMarkFilteringSet` lookup flag); GDEF classifies marks.
    public let ignoreMarks: Bool

    public init(backtrack: [Set<Int>], lookahead: [Set<Int>], mapping: [Int: Int], ignoreMarks: Bool = false) {
        self.backtrack = backtrack
        self.lookahead = lookahead
        self.mapping = mapping
        self.ignoreMarks = ignoreMarks
    }
}
