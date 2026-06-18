//
//  ImageMetadata.swift
//  PureDraw
//

/// Metadata extracted from an image container (PNG, JPEG, or TIFF) without
/// decoding pixels: dimensions, EXIF camera fields, GPS coordinates, and PNG
/// text chunks. Parsing is tolerant: unknown chunks, markers, and tags are
/// skipped, and malformed structures yield `nil` rather than trapping.
public struct ImageMetadata: Equatable, Sendable {
    /// The image container the metadata was read from.
    public enum Format: String, Equatable, Sendable {
        case png
        case jpeg
        case tiff
    }

    /// The container the metadata was read from.
    public let format: Format
    /// The image width in pixels, when the container declares it.
    public let pixelWidth: Int?
    /// The image height in pixels, when the container declares it.
    public let pixelHeight: Int?
    /// EXIF orientation (tag 0x0112), 1 through 8.
    public let orientation: Int?
    /// EXIF camera make (tag 0x010F).
    public let cameraMake: String?
    /// EXIF camera model (tag 0x0110).
    public let cameraModel: String?
    /// EXIF modification date (tag 0x0132), as stored.
    public let dateTime: String?
    /// GPS latitude in signed decimal degrees (south is negative).
    public let gpsLatitude: Double?
    /// GPS longitude in signed decimal degrees (west is negative).
    public let gpsLongitude: Double?
    /// PNG `tEXt` keyword/value pairs.
    public let textFields: [String: String]

    // MARK: - Entry Points

    /// Parses metadata from raw container bytes; `nil` when the format is
    /// not recognized.
    public static func parse(_ bytes: [UInt8]) -> ImageMetadata? {
        if bytes.count >= 8, Array(bytes[0 ..< 8]) == [137, 80, 78, 71, 13, 10, 26, 10] {
            return parsePNG(bytes)
        }
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return parseJPEG(bytes)
        }
        if bytes.count >= 4,
           (bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 42 && bytes[3] == 0) ||
           (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0 && bytes[3] == 42)
        {
            guard let fields = parseTIFF(bytes) else { return nil }
            return ImageMetadata(format: .tiff, fields: fields, textFields: [:])
        }
        return nil
    }

    /// Parses metadata from a data provider.
    public static func parse(from provider: DataProvider) throws -> ImageMetadata? {
        try parse(provider.data())
    }

    private init(format: Format, fields: TIFFFields, textFields: [String: String]) {
        self.format = format
        pixelWidth = fields.width
        pixelHeight = fields.height
        orientation = fields.orientation
        cameraMake = fields.make
        cameraModel = fields.model
        dateTime = fields.dateTime
        gpsLatitude = fields.gpsLatitude
        gpsLongitude = fields.gpsLongitude
        self.textFields = textFields
    }

    // MARK: - PNG

    private static func parsePNG(_ bytes: [UInt8]) -> ImageMetadata? {
        var fields = TIFFFields()
        var text: [String: String] = [:]
        var offset = 8

        while offset + 8 <= bytes.count {
            guard let length = readU32(bytes, at: offset, bigEndian: true),
                  let type = readASCII(bytes, at: offset + 4, count: 4)
            else { break }
            let dataStart = offset + 8
            guard dataStart + length + 4 <= bytes.count else { break }

            switch type {
            case "IHDR":
                fields.width = readU32(bytes, at: dataStart, bigEndian: true)
                fields.height = readU32(bytes, at: dataStart + 4, bigEndian: true)
            case "tEXt":
                let payload = Array(bytes[dataStart ..< dataStart + length])
                if let separator = payload.firstIndex(of: 0) {
                    let keyword = String(decoding: payload[..<separator], as: UTF8.self)
                    let value = String(decoding: payload[payload.index(after: separator)...], as: UTF8.self)
                    if !keyword.isEmpty {
                        text[keyword] = value
                    }
                }
            case "IEND":
                return ImageMetadata(format: .png, fields: fields, textFields: text)
            default:
                break
            }
            offset = dataStart + length + 4
        }
        return ImageMetadata(format: .png, fields: fields, textFields: text)
    }

    // MARK: - JPEG

    private static func parseJPEG(_ bytes: [UInt8]) -> ImageMetadata? {
        var fields = TIFFFields()
        var offset = 2

        while offset + 2 <= bytes.count {
            guard bytes[offset] == 0xFF else { return nil }
            let marker = bytes[offset + 1]

            if marker == 0xD8 || (0xD0 ... 0xD7).contains(marker) || marker == 0x01 {
                offset += 2
                continue
            }
            if marker == 0xD9 { // EOI
                break
            }
            guard let segmentLength = readU16(bytes, at: offset + 2, bigEndian: true),
                  segmentLength >= 2,
                  offset + 2 + segmentLength <= bytes.count
            else { break }

            switch marker {
            case 0xC0, 0xC1, 0xC2, 0xC3: // SOF: baseline and progressive frames
                fields.height = readU16(bytes, at: offset + 5, bigEndian: true)
                fields.width = readU16(bytes, at: offset + 7, bigEndian: true)
            case 0xE1: // APP1, possibly EXIF
                let payloadStart = offset + 4
                if segmentLength >= 8,
                   readASCII(bytes, at: payloadStart, count: 4) == "Exif",
                   bytes[payloadStart + 4] == 0, bytes[payloadStart + 5] == 0
                {
                    let tiffBytes = Array(bytes[(payloadStart + 6) ..< (offset + 2 + segmentLength)])
                    if let exif = parseTIFF(tiffBytes) {
                        fields.merge(exif)
                    }
                }
            default:
                break
            }

            if marker == 0xDA { // start of scan: no more metadata segments
                break
            }
            offset += 2 + segmentLength
        }
        return ImageMetadata(format: .jpeg, fields: fields, textFields: [:])
    }

    // MARK: - TIFF / EXIF

    private struct TIFFFields {
        var width: Int?
        var height: Int?
        var orientation: Int?
        var make: String?
        var model: String?
        var dateTime: String?
        var gpsLatitude: Double?
        var gpsLongitude: Double?

        mutating func merge(_ other: TIFFFields) {
            width = width ?? other.width
            height = height ?? other.height
            orientation = orientation ?? other.orientation
            make = make ?? other.make
            model = model ?? other.model
            dateTime = dateTime ?? other.dateTime
            gpsLatitude = gpsLatitude ?? other.gpsLatitude
            gpsLongitude = gpsLongitude ?? other.gpsLongitude
        }
    }

    private static func parseTIFF(_ bytes: [UInt8]) -> TIFFFields? {
        guard bytes.count >= 8 else { return nil }
        let bigEndian: Bool
        if bytes[0] == 0x4D, bytes[1] == 0x4D {
            bigEndian = true
        } else if bytes[0] == 0x49, bytes[1] == 0x49 {
            bigEndian = false
        } else {
            return nil
        }
        guard readU16(bytes, at: 2, bigEndian: bigEndian) == 42,
              let ifdOffset = readU32(bytes, at: 4, bigEndian: bigEndian)
        else { return nil }

        var fields = TIFFFields()
        var gpsIFDOffset: Int?

        enumerateIFD(bytes, at: ifdOffset, bigEndian: bigEndian) { tag, type, count, entryOffset in
            switch tag {
            case 0x0100: fields.width = readTagInt(bytes, type: type, entryOffset: entryOffset, bigEndian: bigEndian)
            case 0x0101: fields.height = readTagInt(bytes, type: type, entryOffset: entryOffset, bigEndian: bigEndian)
            case 0x0112: fields.orientation = readTagInt(bytes, type: type, entryOffset: entryOffset, bigEndian: bigEndian)
            case 0x010F: fields.make = readTagASCII(bytes, count: count, entryOffset: entryOffset, bigEndian: bigEndian)
            case 0x0110: fields.model = readTagASCII(bytes, count: count, entryOffset: entryOffset, bigEndian: bigEndian)
            case 0x0132: fields.dateTime = readTagASCII(bytes, count: count, entryOffset: entryOffset, bigEndian: bigEndian)
            case 0x8825: gpsIFDOffset = readTagInt(bytes, type: type, entryOffset: entryOffset, bigEndian: bigEndian)
            default: break
            }
        }

        if let gpsOffset = gpsIFDOffset {
            var latitudeRef: String?
            var longitudeRef: String?
            var latitude: Double?
            var longitude: Double?

            enumerateIFD(bytes, at: gpsOffset, bigEndian: bigEndian) { tag, _, count, entryOffset in
                switch tag {
                case 0x0001: latitudeRef = readTagASCII(bytes, count: count, entryOffset: entryOffset, bigEndian: bigEndian)
                case 0x0002: latitude = readTagDegrees(bytes, count: count, entryOffset: entryOffset, bigEndian: bigEndian)
                case 0x0003: longitudeRef = readTagASCII(bytes, count: count, entryOffset: entryOffset, bigEndian: bigEndian)
                case 0x0004: longitude = readTagDegrees(bytes, count: count, entryOffset: entryOffset, bigEndian: bigEndian)
                default: break
                }
            }

            if let latitude {
                fields.gpsLatitude = latitudeRef == "S" ? -latitude : latitude
            }
            if let longitude {
                fields.gpsLongitude = longitudeRef == "W" ? -longitude : longitude
            }
        }
        return fields
    }

    private static func enumerateIFD(
        _ bytes: [UInt8],
        at offset: Int,
        bigEndian: Bool,
        entry handler: (_ tag: Int, _ type: Int, _ count: Int, _ entryOffset: Int) -> Void
    ) {
        guard let entryCount = readU16(bytes, at: offset, bigEndian: bigEndian) else { return }
        for index in 0 ..< entryCount {
            let entryOffset = offset + 2 + index * 12
            guard entryOffset + 12 <= bytes.count,
                  let tag = readU16(bytes, at: entryOffset, bigEndian: bigEndian),
                  let type = readU16(bytes, at: entryOffset + 2, bigEndian: bigEndian),
                  let count = readU32(bytes, at: entryOffset + 4, bigEndian: bigEndian)
            else { return }
            handler(tag, type, count, entryOffset)
        }
    }

    /// Reads a SHORT (3) or LONG (4) tag value; both live left-justified in
    /// the entry's 4-byte value field.
    private static func readTagInt(_ bytes: [UInt8], type: Int, entryOffset: Int, bigEndian: Bool) -> Int? {
        switch type {
        case 3: readU16(bytes, at: entryOffset + 8, bigEndian: bigEndian)
        case 4: readU32(bytes, at: entryOffset + 8, bigEndian: bigEndian)
        default: nil
        }
    }

    /// Reads an ASCII tag: inline when it fits the 4-byte value field,
    /// otherwise at the referenced offset. Trailing NULs are trimmed.
    private static func readTagASCII(_ bytes: [UInt8], count: Int, entryOffset: Int, bigEndian: Bool) -> String? {
        let start: Int
        if count <= 4 {
            start = entryOffset + 8
        } else {
            guard let offset = readU32(bytes, at: entryOffset + 8, bigEndian: bigEndian) else { return nil }
            start = offset
        }
        guard count > 0, start + count <= bytes.count else { return nil }
        var characters = Array(bytes[start ..< start + count])
        while characters.last == 0 {
            characters.removeLast()
        }
        return String(decoding: characters, as: UTF8.self)
    }

    /// Reads a degrees/minutes/seconds RATIONAL triple as decimal degrees.
    private static func readTagDegrees(_ bytes: [UInt8], count: Int, entryOffset: Int, bigEndian: Bool) -> Double? {
        guard count == 3, let valueOffset = readU32(bytes, at: entryOffset + 8, bigEndian: bigEndian) else { return nil }
        var components: [Double] = []
        for index in 0 ..< 3 {
            let rationalOffset = valueOffset + index * 8
            guard let numerator = readU32(bytes, at: rationalOffset, bigEndian: bigEndian),
                  let denominator = readU32(bytes, at: rationalOffset + 4, bigEndian: bigEndian),
                  denominator != 0
            else { return nil }
            components.append(Double(numerator) / Double(denominator))
        }
        return components[0] + components[1] / 60.0 + components[2] / 3600.0
    }

    // MARK: - Byte Reading

    private static func readU16(_ bytes: [UInt8], at offset: Int, bigEndian: Bool) -> Int? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        let first = Int(bytes[offset])
        let second = Int(bytes[offset + 1])
        return bigEndian ? (first << 8) | second : (second << 8) | first
    }

    private static func readU32(_ bytes: [UInt8], at offset: Int, bigEndian: Bool) -> Int? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let b0 = Int(bytes[offset])
        let b1 = Int(bytes[offset + 1])
        let b2 = Int(bytes[offset + 2])
        let b3 = Int(bytes[offset + 3])
        return bigEndian
            ? (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
            : (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
    }

    private static func readASCII(_ bytes: [UInt8], at offset: Int, count: Int) -> String? {
        guard offset >= 0, count > 0, offset + count <= bytes.count else { return nil }
        return String(decoding: bytes[offset ..< offset + count], as: UTF8.self)
    }
}
