/// One GSUB lookup, parsed into the typed substitution it performs, addressed by
/// its index in the font's LookupList. This is the lookup-indexed model the
/// shaping tier applies in lookup-list order: each feature selects a set of
/// lookups, and the shaper applies them by index, with contextual lookups
/// (``Kind/context``) invoking other lookups by index through
/// ``GSUBContextRule/Record``. It is the general form of the per-feature
/// accessors (``Font/singleSubstitutions(feature:restrictTo:)`` and its
/// siblings), which pre-resolve a single feature's lookups into one map; this
/// instead exposes each lookup whole so nested and recursive application is
/// possible.
///
/// Type-7 extension lookups are resolved to their effective type during parsing,
/// so they never appear here. A lookup whose type is not yet modelled is
/// ``Kind/unsupported`` rather than dropped, so the shaper can apply the lookups
/// it understands and skip the rest in order.
///
/// (OpenType GSUB: Lookup table and Lookup Types 1-8.)
public struct GSUBLookup: Equatable, Sendable {
    /// The substitution a lookup performs, by OpenType lookup type.
    public enum Kind: Equatable, Sendable {
        /// Type 1: each covered glyph maps to one substitute.
        case single([Int: Int])
        /// Type 2: each covered glyph expands to an ordered glyph sequence.
        case multiple([Int: [Int]])
        /// Type 3: each covered glyph offers an ordered set of alternates; the
        /// default selection is the first.
        case alternate([Int: [Int]])
        /// Type 4: a glyph sequence is replaced with one ligature glyph.
        case ligature([LigatureSubstitution])
        /// Types 5 and 6: a context invokes nested lookups by index.
        case context([GSUBContextRule])
        /// Type 8: reverse chaining single substitution, applied end to start.
        case reverseChainSingle([ReverseChainingSubstitution])
        /// A lookup type not modelled here; applied as a no-op so lookup order is
        /// preserved.
        case unsupported
    }

    /// The substitution this lookup performs.
    public let kind: Kind
    /// Whether the lookup skips mark glyphs when matching (the `IgnoreMarks`
    /// lookup flag); GDEF classifies marks. Mirrors the flag the contextual and
    /// reverse-chaining values already carry.
    public let ignoreMarks: Bool
    /// The lookup's mark attachment type (the high byte of the lookup flag), or 0
    /// when none. When non-zero, the lookup skips every mark whose GDEF mark
    /// attachment class differs from this type, so a contextual rule can step over
    /// one kind of mark while matching across another. Independent of
    /// ``ignoreMarks``, which skips every mark.
    public let markAttachmentType: Int

    public init(kind: Kind, ignoreMarks: Bool, markAttachmentType: Int = 0) {
        self.kind = kind
        self.ignoreMarks = ignoreMarks
        self.markAttachmentType = markAttachmentType
    }
}
