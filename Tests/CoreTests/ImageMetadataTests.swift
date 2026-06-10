//
//  ImageMetadataTests.swift
//  PureDraw
//

@testable import Core
import Testing

struct ImageMetadataTests {
    @Test func parsesPNGDimensionsAndText() throws {
        var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        // IHDR: 320 x 200, 8-bit RGBA. CRCs are not verified by the parser.
        appendAll(&png, be32(13), ascii("IHDR"), be32(320), be32(200), [8, 6, 0, 0, 0], be32(0))
        var text: [UInt8] = ascii("Title")
        appendAll(&text, [0], ascii("PureDraw"))
        appendAll(&png, be32(text.count), ascii("tEXt"), text, be32(0))
        appendAll(&png, be32(0), ascii("IEND"), be32(0))

        let metadata = try #require(ImageMetadata.parse(png))
        #expect(metadata.format == .png)
        #expect(metadata.pixelWidth == 320)
        #expect(metadata.pixelHeight == 200)
        #expect(metadata.textFields == ["Title": "PureDraw"])
        #expect(metadata.orientation == nil)
    }

    @Test func parsesJPEGWithEXIFAndGPS() throws {
        let tiff = littleEndianEXIF()
        var app1Payload: [UInt8] = ascii("Exif")
        appendAll(&app1Payload, [0, 0], tiff)

        var jpeg: [UInt8] = [0xFF, 0xD8]
        appendAll(&jpeg, [0xFF, 0xE1], be16(2 + app1Payload.count), app1Payload)
        // SOF0: precision 8, 480 x 640, one component.
        appendAll(&jpeg, [0xFF, 0xC0], be16(11), [8], be16(480), be16(640), [1, 0x11, 0, 0])
        appendAll(&jpeg, [0xFF, 0xD9])

        let metadata = try #require(ImageMetadata.parse(jpeg))
        #expect(metadata.format == .jpeg)
        #expect(metadata.pixelWidth == 640)
        #expect(metadata.pixelHeight == 480)
        #expect(metadata.orientation == 6)
        #expect(metadata.cameraMake == "PureDraw")
        #expect(metadata.dateTime == "2026:06:10 12:00:00")
        #expect(metadata.gpsLatitude == 45.5)
        #expect(metadata.gpsLongitude == -13.25)
    }

    @Test func parsesBigEndianTIFF() throws {
        var tiff: [UInt8] = [0x4D, 0x4D, 0, 42]
        appendAll(&tiff, be32(8), be16(3))
        appendAll(&tiff, be16(0x0100), be16(3), be32(1), be16(1024), be16(0)) // width, SHORT
        appendAll(&tiff, be16(0x0101), be16(4), be32(1), be32(768)) // height, LONG
        appendAll(&tiff, be16(0x0112), be16(3), be32(1), be16(3), be16(0)) // orientation
        appendAll(&tiff, be32(0)) // no next IFD

        let metadata = try #require(ImageMetadata.parse(tiff))
        #expect(metadata.format == .tiff)
        #expect(metadata.pixelWidth == 1024)
        #expect(metadata.pixelHeight == 768)
        #expect(metadata.orientation == 3)
    }

    @Test func rejectsUnknownContainers() {
        #expect(ImageMetadata.parse([0, 1, 2, 3, 4, 5, 6, 7, 8]) == nil)
        #expect(ImageMetadata.parse([]) == nil)
    }

    @Test func parsesFromProvider() throws {
        var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        appendAll(&png, be32(13), ascii("IHDR"), be32(16), be32(16), [8, 6, 0, 0, 0], be32(0))
        appendAll(&png, be32(0), ascii("IEND"), be32(0))

        let metadata = try #require(try ImageMetadata.parse(from: DataProvider(data: png)))
        #expect(metadata.pixelWidth == 16)
    }

    @Test func truncatedStructuresDoNotTrap() {
        // A PNG signature with a chunk header promising more bytes than exist.
        var truncated: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        appendAll(&truncated, be32(9999), ascii("IHDR"))
        #expect(ImageMetadata.parse(truncated)?.pixelWidth == nil)

        // A JPEG whose APP1 claims EXIF but holds garbage.
        var jpeg: [UInt8] = [0xFF, 0xD8]
        appendAll(&jpeg, [0xFF, 0xE1], be16(10), ascii("Exif"), [0, 0, 1, 2])
        appendAll(&jpeg, [0xFF, 0xD9])
        #expect(ImageMetadata.parse(jpeg)?.orientation == nil)
    }

    // MARK: - Fixture Builders

    /// Little-endian EXIF block: orientation 6, make "PureDraw", a date, and
    /// GPS 45 deg 30 min North, 13 deg 15 min West.
    private func littleEndianEXIF() -> [UInt8] {
        var makeString: [UInt8] = ascii("PureDraw")
        makeString.append(0) // 9 bytes
        var dateString: [UInt8] = ascii("2026:06:10 12:00:00")
        dateString.append(0) // 20 bytes

        // Layout: header (8), IFD0 with 4 entries (2 + 48 + 4 = 54) -> data at 62.
        let makeOffset = 62
        let dateOffset = makeOffset + makeString.count // 71
        let gpsIFDOffset = dateOffset + dateString.count // 91
        // GPS IFD: 4 entries (2 + 48 + 4 = 54) -> rationals at 145.
        let latitudeOffset = gpsIFDOffset + 54 // 145
        let longitudeOffset = latitudeOffset + 24 // 169

        var tiff: [UInt8] = [0x49, 0x49, 42, 0]
        appendAll(&tiff, le32(8), le16(4))
        appendAll(&tiff, le16(0x010F), le16(2), le32(makeString.count), le32(makeOffset))
        appendAll(&tiff, le16(0x0112), le16(3), le32(1), le16(6), le16(0))
        appendAll(&tiff, le16(0x0132), le16(2), le32(dateString.count), le32(dateOffset))
        appendAll(&tiff, le16(0x8825), le16(4), le32(1), le32(gpsIFDOffset))
        appendAll(&tiff, le32(0)) // no next IFD
        appendAll(&tiff, makeString, dateString)

        appendAll(&tiff, le16(4))
        appendAll(&tiff, le16(0x0001), le16(2), le32(2), ascii("N"), [0, 0, 0])
        appendAll(&tiff, le16(0x0002), le16(5), le32(3), le32(latitudeOffset))
        appendAll(&tiff, le16(0x0003), le16(2), le32(2), ascii("W"), [0, 0, 0])
        appendAll(&tiff, le16(0x0004), le16(5), le32(3), le32(longitudeOffset))
        appendAll(&tiff, le32(0)) // no next IFD
        appendAll(&tiff, le32(45), le32(1), le32(30), le32(1), le32(0), le32(1)) // 45 deg 30 min
        appendAll(&tiff, le32(13), le32(1), le32(15), le32(1), le32(0), le32(1)) // 13 deg 15 min
        return tiff
    }

    private func appendAll(_ buffer: inout [UInt8], _ parts: [UInt8]...) {
        for part in parts {
            buffer.append(contentsOf: part)
        }
    }

    private func ascii(_ string: String) -> [UInt8] {
        Array(string.utf8)
    }

    private func be16(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func be32(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private func le16(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private func le32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }
}
