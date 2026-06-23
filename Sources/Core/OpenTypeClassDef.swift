/// An OpenType Layout Class Definition table: maps a glyph id to a class number,
/// defaulting to class 0 for glyphs not listed. Class definitions group glyphs
/// for class-based GSUB and GPOS lookups and for GDEF glyph classes. Formats 1
/// (a contiguous array) and 2 (sorted ranges) are supported, per the OpenType
/// specification.
struct OpenTypeClassDef: Equatable {
    private let classByGlyph: [Int: Int]

    /// Parses a Class Definition table at `offset` in `data`. Returns `nil` if
    /// the table is truncated or uses an unknown format.
    init?(data: [UInt8], offset: Int) {
        guard let format = OpenTypeReader.u16(data, at: offset) else { return nil }
        var map: [Int: Int] = [:]
        switch format {
        case 1:
            guard let startGlyph = OpenTypeReader.u16(data, at: offset + 2),
                  let glyphCount = OpenTypeReader.u16(data, at: offset + 4)
            else {
                return nil
            }
            for index in 0 ..< glyphCount {
                guard let value = OpenTypeReader.u16(data, at: offset + 6 + index * 2) else { return nil }
                if value != 0 {
                    map[startGlyph + index] = value
                }
            }
        case 2:
            guard let rangeCount = OpenTypeReader.u16(data, at: offset + 2) else { return nil }
            for rangeIndex in 0 ..< rangeCount {
                let record = offset + 4 + rangeIndex * 6
                guard let start = OpenTypeReader.u16(data, at: record),
                      let end = OpenTypeReader.u16(data, at: record + 2),
                      let value = OpenTypeReader.u16(data, at: record + 4),
                      start <= end
                else {
                    return nil
                }
                if value != 0 {
                    var glyph = start
                    while glyph <= end {
                        map[glyph] = value
                        glyph += 1
                    }
                }
            }
        default:
            return nil
        }
        classByGlyph = map
    }

    /// The class of `glyph`, or 0 if the glyph is not assigned a class.
    func classValue(forGlyph glyph: Int) -> Int {
        classByGlyph[glyph] ?? 0
    }
}
