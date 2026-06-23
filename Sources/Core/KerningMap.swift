/// Kerning adjustments between glyph pairs, extracted from a font's kerning
/// data. This is the typed boundary the shaping tier (PureText) consumes:
/// PureDraw parses the font tables, this value carries the result. Adjustments
/// are in font units; multiply by `size / unitsPerEm` for user space.
public struct KerningMap: Equatable, Sendable {
    /// Explicit pair adjustments keyed by ``key(firstGlyph:secondGlyph:)``, in
    /// font units (from PairPos format 1 and the legacy `kern` table).
    public let adjustments: [UInt64: Int]
    /// Class-based subtables (from PairPos format 2), resolved on demand.
    public let classSubtables: [KerningClassSubtable]

    public init(adjustments: [UInt64: Int], classSubtables: [KerningClassSubtable] = []) {
        self.adjustments = adjustments
        self.classSubtables = classSubtables
    }

    /// The horizontal advance adjustment to insert between two glyphs, in font
    /// units (0 when the pair is not kerned). Explicit pairs take precedence over
    /// class-based subtables.
    public func adjustment(firstGlyph: Int, secondGlyph: Int) -> Double {
        guard firstGlyph >= 0, secondGlyph >= 0 else { return 0 }
        if let pair = adjustments[Self.key(firstGlyph: firstGlyph, secondGlyph: secondGlyph)] {
            return Double(pair)
        }
        for subtable in classSubtables {
            let value = subtable.adjustment(firstGlyph: firstGlyph, secondGlyph: secondGlyph)
            if value != 0 {
                return Double(value)
            }
        }
        return 0
    }

    /// Whether the font carries no kerning.
    public var isEmpty: Bool {
        adjustments.isEmpty && classSubtables.isEmpty
    }

    /// The dictionary key for a glyph pair, exposed so parsers and consumers
    /// share one encoding.
    public static func key(firstGlyph: Int, secondGlyph: Int) -> UInt64 {
        UInt64(firstGlyph) << 32 | UInt64(secondGlyph)
    }
}
