//
//  PNGEncoder.swift
//  PureDraw
//

import Core

/// Encodes an `Image` into PNG data without external dependencies.
///
/// Output is always 8-bit RGBA (PNG color type 6) with filter type 0 on every
/// scanline. The zlib stream uses stored (uncompressed) deflate blocks, which
/// keeps the encoder small and standards-correct; pixels are decoded through
/// `Image.pixelColor(x:y:)`, so any supported source layout round-trips to
/// straight (non-premultiplied) RGBA.
public enum PNGEncoder {
    public static func encode(_ image: Image) -> [UInt8] {
        var raw: [UInt8] = []
        raw.reserveCapacity(image.height * (1 + image.width * 4))
        for y in 0 ..< image.height {
            raw.append(0) // filter type: none
            for x in 0 ..< image.width {
                let color = image.pixelColor(x: x, y: y)
                raw.append(channelByte(color.red))
                raw.append(channelByte(color.green))
                raw.append(channelByte(color.blue))
                raw.append(channelByte(color.alpha))
            }
        }

        var ihdr: [UInt8] = []
        appendBigEndian(UInt32(image.width), to: &ihdr)
        appendBigEndian(UInt32(image.height), to: &ihdr)
        ihdr.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit, RGBA, deflate, filter 0, no interlace

        var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        appendChunk(type: "IHDR", data: ihdr, to: &png)
        appendChunk(type: "IDAT", data: zlibStored(raw), to: &png)
        appendChunk(type: "IEND", data: [], to: &png)
        return png
    }

    // MARK: - Building Blocks

    private static func channelByte(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, Int((value * 255.0).rounded()))))
    }

    private static func appendBigEndian(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8((value >> 24) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }

    private static func appendChunk(type: String, data: [UInt8], to png: inout [UInt8]) {
        let typeBytes = Array(type.utf8)
        appendBigEndian(UInt32(data.count), to: &png)
        png.append(contentsOf: typeBytes)
        png.append(contentsOf: data)
        appendBigEndian(crc32(typeBytes + data), to: &png)
    }

    /// Wraps raw bytes in a zlib stream of stored (uncompressed) deflate blocks.
    private static func zlibStored(_ raw: [UInt8]) -> [UInt8] {
        var stream: [UInt8] = [0x78, 0x01] // deflate, 32K window, no preset dictionary
        var offset = 0
        repeat {
            let blockLength = min(65535, raw.count - offset)
            let isFinal = offset + blockLength == raw.count
            stream.append(isFinal ? 1 : 0)
            stream.append(UInt8(blockLength & 0xFF))
            stream.append(UInt8((blockLength >> 8) & 0xFF))
            stream.append(UInt8(~blockLength & 0xFF))
            stream.append(UInt8((~blockLength >> 8) & 0xFF))
            stream.append(contentsOf: raw[offset ..< offset + blockLength])
            offset += blockLength
        } while offset < raw.count
        appendBigEndian(adler32(raw), to: &stream)
        return stream
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { n in
        var c = UInt32(n)
        for _ in 0 ..< 8 {
            c = (c & 1) == 1 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}
