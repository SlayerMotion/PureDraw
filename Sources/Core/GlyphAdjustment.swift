/// A GPOS single positioning adjustment (lookup type 1) for one glyph, in font
/// units. `xPlacement`/`yPlacement` shift the glyph away from the pen without
/// moving the pen; `xAdvance`/`yAdvance` change how far the pen moves past it.
/// This is the typed boundary the shaping tier consumes: PureDraw parses the GPOS
/// SinglePos subtable, this value carries the adjustment for the positioner to add
/// to a glyph's offset and advance.
public struct GlyphAdjustment: Equatable, Sendable {
    /// Horizontal placement shift, in font units (does not move the pen).
    public let xPlacement: Int
    /// Vertical placement shift, in font units (does not move the pen).
    public let yPlacement: Int
    /// Change to the horizontal advance, in font units.
    public let xAdvance: Int
    /// Change to the vertical advance, in font units (vertical layout).
    public let yAdvance: Int

    public init(xPlacement: Int = 0, yPlacement: Int = 0, xAdvance: Int = 0, yAdvance: Int = 0) {
        self.xPlacement = xPlacement
        self.yPlacement = yPlacement
        self.xAdvance = xAdvance
        self.yAdvance = yAdvance
    }

    /// Whether the adjustment changes nothing, so it need not be stored or applied.
    public var isZero: Bool {
        xPlacement == 0 && yPlacement == 0 && xAdvance == 0 && yAdvance == 0
    }
}
