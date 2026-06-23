/// A GSUB chaining contextual substitution rule (lookup type 6, format 3): a
/// glyph is substituted only when its neighbours match a context. The rule holds
/// three coverage sequences and the nested substitutions to apply when they all
/// match. This is the typed boundary the shaping tier consumes: PureDraw parses
/// the GSUB table and resolves the nested lookups, this value answers whether a
/// position matches and what to substitute.
///
/// Bounded to format 3 (each context position is a coverage set) with nested
/// type-1 single substitutions, the common case (an Arabic `rclt` rule that lifts
/// a vowel mark to a high variant when it follows a base letter). Format 1 and 2
/// contexts, and nested lookups of other types, are not represented.
public struct ChainingSubstitution: Equatable, Sendable {
    /// A nested substitution: at `sequenceIndex` within the matched input, replace
    /// the glyph through `mapping` (a resolved type-1 single substitution).
    public struct Action: Equatable, Sendable {
        public let sequenceIndex: Int
        public let mapping: [Int: Int]
        public init(sequenceIndex: Int, mapping: [Int: Int]) {
            self.sequenceIndex = sequenceIndex
            self.mapping = mapping
        }
    }

    /// The glyphs that must precede the input, ordered from the one nearest the
    /// input outward (the OpenType backtrack order).
    public let backtrack: [Set<Int>]
    /// The glyphs of the matched sequence, in text order.
    public let input: [Set<Int>]
    /// The glyphs that must follow the input, in text order.
    public let lookahead: [Set<Int>]
    /// The substitutions to apply when the context matches.
    public let actions: [Action]
    /// Whether the lookup skips mark glyphs when matching the context (the
    /// `IgnoreMarks` or `UseMarkFilteringSet` lookup flag): a base before a fatha
    /// still matches as the backtrack even when a mark sits between them. The
    /// matcher skips marks accordingly; the glyph classification comes from GDEF.
    public let ignoreMarks: Bool

    public init(backtrack: [Set<Int>], input: [Set<Int>], lookahead: [Set<Int>], actions: [Action], ignoreMarks: Bool = false) {
        self.backtrack = backtrack
        self.input = input
        self.lookahead = lookahead
        self.actions = actions
        self.ignoreMarks = ignoreMarks
    }

    /// Whether `glyphs` match this rule with the input starting at `index`: each
    /// input position is covered, each backtrack glyph (reading backward) is
    /// covered, and each lookahead glyph (reading forward past the input) is
    /// covered. Matching is positional, with no glyph skipping.
    public func matches(_ glyphs: [Int], at index: Int) -> Bool {
        guard index + input.count <= glyphs.count else { return false }
        for offset in input.indices where !input[offset].contains(glyphs[index + offset]) {
            return false
        }
        guard index - backtrack.count >= 0 else { return false }
        for offset in backtrack.indices where !backtrack[offset].contains(glyphs[index - 1 - offset]) {
            return false
        }
        let lookaheadStart = index + input.count
        guard lookaheadStart + lookahead.count <= glyphs.count else { return false }
        for offset in lookahead.indices where !lookahead[offset].contains(glyphs[lookaheadStart + offset]) {
            return false
        }
        return true
    }
}
