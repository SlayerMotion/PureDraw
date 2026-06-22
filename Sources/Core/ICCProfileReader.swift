//
//  ICCProfileReader.swift
//  PureDraw
//

/// Parses the bytes of an ICC profile (ICC.1) into an ``ICCProfile``. ICC data is big-endian: a 128-byte
/// header, then a tag table of `(signature, offset, size)` triples pointing at typed elements. This
/// reads the header essentials and the matrix-RGB tags (`wtpt`, `rXYZ`/`gXYZ`/`bXYZ` as `XYZType`,
/// `rTRC`/`gTRC`/`bTRC` as `curveType` or `parametricCurveType`). Tags it does not model are skipped, so
/// a profile is read for as much as the matrix-RGB pipeline needs.
public struct ICCProfileReader {
    public init() {}

    /// Reads the profile, or `nil` when the bytes are not a recognizable ICC profile (no `acsp`
    /// signature, or too short for the header and tag table).
    public func read(_ data: [UInt8]) -> ICCProfile? {
        guard data.count >= 132, signature(data, 36) == "acsp" else { return nil }

        let deviceClass = signature(data, 12)
        let colorSpace = signature(data, 16)
        let connectionSpace = signature(data, 20)
        let renderingIntent = Int(uint32(data, 64))

        let tagCount = Int(uint32(data, 128))
        guard tagCount >= 0, 132 + tagCount * 12 <= data.count else { return nil }

        var tags: [String: (offset: Int, size: Int)] = [:]
        for i in 0 ..< tagCount {
            let entry = 132 + i * 12
            let sig = signature(data, entry)
            let offset = Int(uint32(data, entry + 4))
            let size = Int(uint32(data, entry + 8))
            if offset + 8 <= data.count { tags[sig] = (offset, size) }
        }

        let white = tags["wtpt"].flatMap { xyz(data, $0.offset) } ?? XYZColor(x: 0.9642, y: 1.0, z: 0.8249)
        return ICCProfile(
            deviceClass: deviceClass,
            colorSpace: colorSpace,
            connectionSpace: connectionSpace,
            renderingIntent: renderingIntent,
            whitePoint: white,
            redColumn: tags["rXYZ"].flatMap { xyz(data, $0.offset) },
            greenColumn: tags["gXYZ"].flatMap { xyz(data, $0.offset) },
            blueColumn: tags["bXYZ"].flatMap { xyz(data, $0.offset) },
            redCurve: tags["rTRC"].flatMap { curve(data, $0.offset) },
            greenCurve: tags["gTRC"].flatMap { curve(data, $0.offset) },
            blueCurve: tags["bTRC"].flatMap { curve(data, $0.offset) }
        )
    }

    // MARK: Typed elements

    /// An `XYZType`: `'XYZ '` + 4 reserved + one `XYZNumber` (three s15Fixed16).
    private func xyz(_ data: [UInt8], _ offset: Int) -> XYZColor? {
        guard offset + 20 <= data.count, signature(data, offset) == "XYZ " else { return nil }
        return XYZColor(
            x: s15Fixed16(data, offset + 8),
            y: s15Fixed16(data, offset + 12),
            z: s15Fixed16(data, offset + 16)
        )
    }

    /// A `curveType` (`curv`) or `parametricCurveType` (`para`) tone curve.
    private func curve(_ data: [UInt8], _ offset: Int) -> ICCToneCurve? {
        switch signature(data, offset) {
        case "curv":
            guard offset + 12 <= data.count else { return nil }
            let count = Int(uint32(data, offset + 8))
            if count == 0 { return .identity }
            guard offset + 12 + count * 2 <= data.count else { return nil }
            if count == 1 {
                // A single entry is a u8Fixed8 gamma value.
                return .gamma(Double(uint16(data, offset + 12)) / 256.0)
            }
            let entries = (0 ..< count).map { Double(uint16(data, offset + 12 + $0 * 2)) / 65535.0 }
            return .table(entries)
        case "para":
            guard offset + 12 <= data.count else { return nil }
            let functionType = Int(uint16(data, offset + 8))
            let parameterCount = [0: 1, 1: 3, 2: 4, 3: 5, 4: 7][functionType] ?? 0
            guard offset + 12 + parameterCount * 4 <= data.count else { return nil }
            let parameters = (0 ..< parameterCount).map { s15Fixed16(data, offset + 12 + $0 * 4) }
            return .parametric(functionType: functionType, parameters: parameters)
        default:
            return nil
        }
    }

    // MARK: Big-endian primitives

    private func uint16(_ data: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private func uint32(_ data: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private func s15Fixed16(_ data: [UInt8], _ offset: Int) -> Double {
        Double(Int32(bitPattern: uint32(data, offset))) / 65536.0
    }

    private func signature(_ data: [UInt8], _ offset: Int) -> String {
        guard offset + 4 <= data.count else { return "" }
        return String(decoding: data[offset ..< offset + 4], as: UTF8.self)
    }
}
