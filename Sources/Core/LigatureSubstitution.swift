/// A ligature substitution rule from a font's GSUB table: an input sequence of
/// glyphs that the shaper replaces with a single ligature glyph (for example the
/// glyphs for `f` and `i` becoming the `fi` ligature). This is the typed
/// boundary the shaping tier (PureText) consumes: PureDraw parses the GSUB
/// table, this value carries the rule.
public struct LigatureSubstitution: Equatable, Sendable {
    /// The input glyph sequence, in order, length two or more. The first element
    /// is the Coverage (first) glyph; the rest are the ligature's components.
    public let components: [Int]
    /// The glyph the sequence is replaced with.
    public let ligatureGlyph: Int

    public init(components: [Int], ligatureGlyph: Int) {
        self.components = components
        self.ligatureGlyph = ligatureGlyph
    }
}
