/// A GPOS contextual positioning rule, format 3: a glyph's position is adjusted
/// only when a context matches. It represents both the chained rule (lookup type
/// 8: backtrack, input, and lookahead coverage sequences) and the plain contextual
/// rule (lookup type 7: an input sequence with empty backtrack and lookahead). It
/// is the positioning analogue of ``ChainingSubstitution``: the nested lookups it
/// names are resolved into per-position glyph adjustments. This is the typed
/// boundary the shaping tier consumes.
///
/// Bounded to format 3 (each context position is a coverage set) with nested
/// type-1 single-adjustment lookups, the common case. Formats 1 and 2, and nested
/// lookups of other positioning types, are not represented (the same bound the
/// contextual *substitution* rules carry).
public struct ContextualPositioning: Equatable, Sendable {
    /// A nested adjustment: at `sequenceIndex` within the matched input, adjust the
    /// glyph by `adjustments[glyph]` (a resolved type-1 single positioning).
    public struct Action: Equatable, Sendable {
        public let sequenceIndex: Int
        public let adjustments: [Int: GlyphAdjustment]
        public init(sequenceIndex: Int, adjustments: [Int: GlyphAdjustment]) {
            self.sequenceIndex = sequenceIndex
            self.adjustments = adjustments
        }
    }

    /// The glyphs that must precede the input, nearest the input first.
    public let backtrack: [Set<Int>]
    /// The glyphs of the matched sequence, in text order.
    public let input: [Set<Int>]
    /// The glyphs that must follow the input, in text order.
    public let lookahead: [Set<Int>]
    /// The adjustments to apply when the context matches.
    public let actions: [Action]
    /// Whether the lookup skips mark glyphs when matching the context.
    public let ignoreMarks: Bool

    public init(
        backtrack: [Set<Int>],
        input: [Set<Int>],
        lookahead: [Set<Int>],
        actions: [Action],
        ignoreMarks: Bool = false
    ) {
        self.backtrack = backtrack
        self.input = input
        self.lookahead = lookahead
        self.actions = actions
        self.ignoreMarks = ignoreMarks
    }

    /// Whether the input, backtrack, and lookahead all match `glyphs` with the
    /// input beginning at `index` (no mark skipping, the direct test the shaping
    /// tier refines).
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
