/// Big-endian readers for the OpenType Layout tables (GSUB, GPOS, GDEF, kern).
///
/// These tables share the sfnt big-endian integer encoding. The reader is
/// Foundation-free and bounds-checked: every read returns `nil` rather than
/// trapping when the offset is out of range, so a malformed font degrades to
/// "no data" instead of crashing.
enum OpenTypeReader {
    /// An unsigned 16-bit big-endian integer at `offset`, or `nil` if out of range.
    static func u16(_ data: [UInt8], at offset: Int) -> Int? {
        guard offset >= 0, offset + 1 < data.count else { return nil }
        return Int(data[offset]) << 8 | Int(data[offset + 1])
    }

    /// A signed 16-bit big-endian integer at `offset`, or `nil` if out of range.
    static func i16(_ data: [UInt8], at offset: Int) -> Int? {
        guard let value = u16(data, at: offset) else { return nil }
        return value >= 0x8000 ? value - 0x10000 : value
    }

    /// An unsigned 32-bit big-endian integer at `offset`, or `nil` if out of range.
    static func u32(_ data: [UInt8], at offset: Int) -> Int? {
        guard offset >= 0, offset + 3 < data.count else { return nil }
        return Int(data[offset]) << 24
            | Int(data[offset + 1]) << 16
            | Int(data[offset + 2]) << 8
            | Int(data[offset + 3])
    }
}
