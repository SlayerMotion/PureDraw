/// A GSUB contextual substitution rule in the lookup-indexed model: a context
/// that, when it matches, applies one or more nested lookups by index at named
/// positions within the matched input. It unifies the plain contextual lookup
/// (type 5, with empty backtrack and lookahead) and the chaining contextual
/// lookup (type 6), and it carries the three OpenType subtable formats: format 1
/// (glyph sequences), format 2 (class sequences, expanded here to glyph sets),
/// and format 3 (coverage sequences).
///
/// Unlike ``ChainingSubstitution``, whose `actions` pre-resolve a nested type-1
/// single substitution into a glyph map, this rule keeps the nested reference as
/// a ``Record`` naming a lookup index, so the shaping tier can apply a nested
/// lookup of any type, including another contextual lookup (recursion). That is
/// what Nastaliq's `rlig` needs: its format 1 and 2 contextual rules invoke both
/// type-1 single substitutions and further type-6 chaining lookups.
///
/// (OpenType GSUB: Lookup Types 5 and 6, "Contextual" and "Chained Contexts
/// Substitution", formats 1, 2, and 3.)
public struct GSUBContextRule: Equatable, Sendable {
    /// A nested lookup invocation: apply the lookup at `lookupIndex` to the glyph
    /// at the matched-input position `sequenceIndex` (an index into this rule's
    /// `input` sequence, 0 based). The OpenType `SequenceLookupRecord`.
    public struct Record: Equatable, Sendable {
        public let sequenceIndex: Int
        public let lookupIndex: Int
        public init(sequenceIndex: Int, lookupIndex: Int) {
            self.sequenceIndex = sequenceIndex
            self.lookupIndex = lookupIndex
        }
    }

    /// The glyphs that must precede the input, ordered from the one nearest the
    /// input outward (the OpenType backtrack order). Empty for a type-5 rule.
    public let backtrack: [Set<Int>]
    /// The glyphs of the matched sequence, in text order.
    public let input: [Set<Int>]
    /// The glyphs that must follow the input, in text order. Empty for a type-5
    /// rule.
    public let lookahead: [Set<Int>]
    /// The nested lookups to apply, in the order the font lists them, when the
    /// context matches.
    public let records: [Record]

    public init(backtrack: [Set<Int>], input: [Set<Int>], lookahead: [Set<Int>], records: [Record]) {
        self.backtrack = backtrack
        self.input = input
        self.lookahead = lookahead
        self.records = records
    }
}
