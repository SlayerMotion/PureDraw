/// Kerning adjustments between glyph pairs, extracted from a font's kerning
/// data. This is the typed boundary the shaping tier (PureText) consumes:
/// PureDraw parses the font tables, this value carries the result. Adjustments
/// are in font units; multiply by `size / unitsPerEm` for user space.
public struct KerningMap: Equatable, Sendable {
    /// Pair adjustments keyed by ``key(firstGlyph:secondGlyph:)``, in font units.
    public let adjustments: [UInt64: Int]

    public init(adjustments: [UInt64: Int]) {
        self.adjustments = adjustments
    }

    /// The horizontal advance adjustment to insert between two glyphs, in font
    /// units (0 when the pair is not kerned).
    public func adjustment(firstGlyph: Int, secondGlyph: Int) -> Double {
        guard firstGlyph >= 0, secondGlyph >= 0 else { return 0 }
        return Double(adjustments[Self.key(firstGlyph: firstGlyph, secondGlyph: secondGlyph)] ?? 0)
    }

    /// Whether the font carries no kerning pairs.
    public var isEmpty: Bool {
        adjustments.isEmpty
    }

    /// The dictionary key for a glyph pair, exposed so parsers and consumers
    /// share one encoding.
    public static func key(firstGlyph: Int, secondGlyph: Int) -> UInt64 {
        UInt64(firstGlyph) << 32 | UInt64(secondGlyph)
    }
}
