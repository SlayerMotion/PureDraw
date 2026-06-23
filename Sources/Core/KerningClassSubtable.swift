/// A class-based kerning subtable: the resolved form of a GPOS PairPos format 2
/// table. Rather than enumerate every glyph pair (which would be enormous), it
/// keeps the two class definitions and the class-pair value matrix, and resolves
/// a pair on demand. The first glyph must be covered for the subtable to apply.
public struct KerningClassSubtable: Equatable, Sendable {
    /// The first glyphs this subtable applies to (the PairPos Coverage).
    public let coveredFirstGlyphs: Set<Int>
    /// The class of each first glyph (absent glyphs are class 0).
    public let firstClasses: [Int: Int]
    /// The class of each second glyph (absent glyphs are class 0).
    public let secondClasses: [Int: Int]
    /// The number of second-glyph classes (the row stride of `xAdvances`).
    public let secondClassCount: Int
    /// The x-advance adjustment per (firstClass, secondClass), row-major, in font units.
    public let xAdvances: [Int]

    public init(
        coveredFirstGlyphs: Set<Int>,
        firstClasses: [Int: Int],
        secondClasses: [Int: Int],
        secondClassCount: Int,
        xAdvances: [Int]
    ) {
        self.coveredFirstGlyphs = coveredFirstGlyphs
        self.firstClasses = firstClasses
        self.secondClasses = secondClasses
        self.secondClassCount = secondClassCount
        self.xAdvances = xAdvances
    }

    /// The x-advance adjustment for a glyph pair in font units (0 if not covered
    /// or the class pair has no adjustment).
    public func adjustment(firstGlyph: Int, secondGlyph: Int) -> Int {
        guard coveredFirstGlyphs.contains(firstGlyph) else { return 0 }
        let firstClass = firstClasses[firstGlyph] ?? 0
        let secondClass = secondClasses[secondGlyph] ?? 0
        let index = firstClass * secondClassCount + secondClass
        guard index >= 0, index < xAdvances.count else { return 0 }
        return xAdvances[index]
    }
}
