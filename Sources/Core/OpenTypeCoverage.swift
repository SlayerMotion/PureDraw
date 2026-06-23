/// An OpenType Layout Coverage table: maps a glyph id to a coverage index, or
/// reports that the glyph is not covered. Coverage tables select which glyphs a
/// lookup applies to, in both GSUB and GPOS. Formats 1 (a sorted glyph list) and
/// 2 (sorted ranges) are supported, per the OpenType specification.
struct OpenTypeCoverage: Equatable {
    private let indexByGlyph: [Int: Int]

    /// Parses a Coverage table at `offset` in `data`. Returns `nil` if the table
    /// is truncated or uses an unknown format.
    init?(data: [UInt8], offset: Int) {
        guard let format = OpenTypeReader.u16(data, at: offset) else { return nil }
        var map: [Int: Int] = [:]
        switch format {
        case 1:
            guard let glyphCount = OpenTypeReader.u16(data, at: offset + 2) else { return nil }
            for index in 0 ..< glyphCount {
                guard let glyph = OpenTypeReader.u16(data, at: offset + 4 + index * 2) else { return nil }
                map[glyph] = index
            }
        case 2:
            guard let rangeCount = OpenTypeReader.u16(data, at: offset + 2) else { return nil }
            for rangeIndex in 0 ..< rangeCount {
                let record = offset + 4 + rangeIndex * 6
                guard let start = OpenTypeReader.u16(data, at: record),
                      let end = OpenTypeReader.u16(data, at: record + 2),
                      let startCoverageIndex = OpenTypeReader.u16(data, at: record + 4),
                      start <= end
                else {
                    return nil
                }
                var glyph = start
                var coverageIndex = startCoverageIndex
                while glyph <= end {
                    map[glyph] = coverageIndex
                    glyph += 1
                    coverageIndex += 1
                }
            }
        default:
            return nil
        }
        indexByGlyph = map
        var ordered = [Int](repeating: 0, count: map.count)
        for (glyph, index) in map where index >= 0 && index < map.count {
            ordered[index] = glyph
        }
        glyphsByIndex = ordered
    }

    private let glyphsByIndex: [Int]

    /// The coverage index of `glyph`, or `nil` if the glyph is not covered.
    func index(forGlyph glyph: Int) -> Int? {
        indexByGlyph[glyph]
    }

    /// The glyph at a coverage index, or `nil` if out of range. Lets a lookup
    /// walk its per-coverage-index records (for example PairPos format 1).
    func glyph(atIndex index: Int) -> Int? {
        guard index >= 0, index < glyphsByIndex.count else { return nil }
        return glyphsByIndex[index]
    }

    /// The number of glyphs covered.
    var count: Int {
        indexByGlyph.count
    }
}
