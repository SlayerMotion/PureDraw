//
//  WOFFDecoder.swift
//  PureDraw
//

/// Decodes a WOFF 1.0 font wrapper into the equivalent sfnt (TrueType/OpenType) bytes, which
/// `Font(data:)` then parses (PureDraw #75). WOFF is an sfnt whose tables are individually
/// zlib-compressed (or stored when compression would not help) behind a small header and table
/// directory; decoding is the inverse of that wrapping. The metadata and private blocks are
/// ignored. WOFF2 (Brotli + a transformed glyf/loca) is a separate format and not handled here.
public enum WOFFDecoder {
    public enum Error: Swift.Error, Equatable {
        case notWOFF
        case malformed(String)
    }

    private static let signature = 0x774F_4646 // 'wOFF'

    /// Reassembles the sfnt bytes from a WOFF font.
    public static func sfnt(from woff: [UInt8]) throws -> [UInt8] {
        guard woff.count >= 44, be32(woff, 0) == signature else { throw Error.notWOFF }
        let flavor = be32(woff, 4)
        let numTables = be16(woff, 12)
        guard numTables > 0, woff.count >= 44 + numTables * 20 else { throw Error.malformed("WOFF table directory is truncated") }

        struct Table { let tag: [UInt8]
            let data: [UInt8]
            let checksum: UInt32
        }
        var tables: [Table] = []
        for i in 0 ..< numTables {
            let base = 44 + i * 20
            let tag = Array(woff[base ..< base + 4])
            let offset = be32(woff, base + 4)
            let compLength = be32(woff, base + 8)
            let origLength = be32(woff, base + 12)
            let checksum = UInt32(be32(woff, base + 16))
            guard offset >= 0, compLength >= 0, offset + compLength <= woff.count else {
                throw Error.malformed("WOFF table \(String(decoding: tag, as: UTF8.self)) overruns the file")
            }
            let raw = Array(woff[offset ..< offset + compLength])
            let data: [UInt8]
            if compLength < origLength {
                guard let inflated = Inflate.zlib(raw), inflated.count == origLength else {
                    throw Error.malformed("WOFF table \(String(decoding: tag, as: UTF8.self)) failed to inflate")
                }
                data = inflated
            } else {
                data = raw
            }
            tables.append(Table(tag: tag, data: data, checksum: checksum))
        }
        // The sfnt table records must be in ascending tag order.
        tables.sort { lexicographicallyBefore($0.tag, $1.tag) }

        let (searchRange, entrySelector, rangeShift) = sfntSearchParameters(numTables)
        var sfnt: [UInt8] = []
        sfnt += be32Bytes(UInt32(truncatingIfNeeded: flavor))
        sfnt += be16Bytes(numTables) + be16Bytes(searchRange) + be16Bytes(entrySelector) + be16Bytes(rangeShift)

        // Table records, with offsets into the 4-byte-aligned data that follows the directory.
        var dataOffset = 12 + numTables * 16
        for table in tables {
            sfnt += table.tag
            sfnt += be32Bytes(table.checksum)
            sfnt += be32Bytes(UInt32(dataOffset))
            sfnt += be32Bytes(UInt32(table.data.count))
            dataOffset += aligned4(table.data.count)
        }
        // Table data, each padded to a 4-byte boundary.
        for table in tables {
            sfnt += table.data
            sfnt += [UInt8](repeating: 0, count: aligned4(table.data.count) - table.data.count)
        }
        return sfnt
    }

    // MARK: - Helpers

    private static func be32(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
    }

    private static func be16(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) << 8 | Int(b[o + 1])
    }

    private static func be32Bytes(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }

    private static func be16Bytes(_ v: Int) -> [UInt8] {
        [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }

    private static func aligned4(_ n: Int) -> Int {
        (n + 3) & ~3
    }

    private static func lexicographicallyBefore(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        for i in 0 ..< min(a.count, b.count) where a[i] != b[i] {
            return a[i] < b[i]
        }
        return a.count < b.count
    }

    /// The sfnt offset-table binary-search fields: searchRange = 16 * 2^floor(log2(n)),
    /// entrySelector = floor(log2(n)), rangeShift = 16*n - searchRange.
    private static func sfntSearchParameters(_ n: Int) -> (searchRange: Int, entrySelector: Int, rangeShift: Int) {
        var pow2 = 1, selector = 0
        while pow2 * 2 <= n {
            pow2 *= 2
            selector += 1
        }
        let searchRange = pow2 * 16
        return (searchRange, selector, n * 16 - searchRange)
    }
}

public extension Font {
    /// Parses a WOFF 1.0 font by reassembling its sfnt tables and decoding the result.
    init(woff bytes: [UInt8]) throws {
        try self.init(data: WOFFDecoder.sfnt(from: bytes))
    }
}
