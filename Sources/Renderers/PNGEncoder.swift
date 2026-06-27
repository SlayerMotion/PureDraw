//
//  PNGEncoder.swift
//  PureDraw
//

import Core

/// Encodes an `Image` into PNG data without external dependencies.
///
/// Output is always 8-bit RGBA (PNG color type 6). Each scanline is filtered with
/// the best of the five PNG filters, then the stream is DEFLATE-compressed via
/// ``Deflate``; pixels are decoded through `Image.pixelColor(x:y:)`, so any
/// supported source layout round-trips to straight (non-premultiplied) RGBA.
public enum PNGEncoder {
    /// Encodes the image and writes the result to a data consumer.
    public static func encode(_ image: Image, to consumer: DataConsumer) {
        consumer.write(encode(image))
    }

    /// Encodes an RGBA ``Image`` as the bytes of a PNG file.
    public static func encode(_ image: Image) -> [UInt8] {
        var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        appendChunk(type: "IHDR", data: ihdr(width: image.width, height: image.height), to: &png)
        appendChunk(type: "IDAT", data: zlib(rawScanlines(image)), to: &png)
        appendChunk(type: "IEND", data: [], to: &png)
        return png
    }

    /// Encodes `frames` as an animated PNG (APNG) that loops forever, each frame
    /// shown for `frameDelay` seconds. Frames are assumed to share the first
    /// frame's dimensions. A single frame falls back to a plain PNG.
    ///
    /// APNG is a backwards-compatible PNG extension (a viewer that ignores the
    /// animation chunks shows the first frame), so the output is a single playable
    /// file that needs no external encoder or dependency.
    public static func encodeAnimated(_ frames: [Image], frameDelay: Double) -> [UInt8] {
        guard let first = frames.first else { return [] }
        guard frames.count > 1 else { return encode(first) }

        let width = first.width
        let height = first.height
        // Sanitize the delay: Int(non-finite) traps, and a negative delay is meaningless.
        let safeDelayMs = frameDelay.isFinite ? max(0, frameDelay * 1000) : 0
        let delayNumerator = UInt16(min(65535, max(0, Int(safeDelayMs.rounded()))))
        let delayDenominator: UInt16 = 1000

        var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        appendChunk(type: "IHDR", data: ihdr(width: width, height: height), to: &png)

        // acTL: animation control. num_plays 0 loops forever.
        var actl: [UInt8] = []
        appendBigEndian(UInt32(frames.count), to: &actl)
        appendBigEndian(0, to: &actl)
        appendChunk(type: "acTL", data: actl, to: &png)

        var sequence: UInt32 = 0
        for (index, frame) in frames.enumerated() {
            // fcTL: frame control. dispose 1 (clear to background) + blend 0 (source)
            // makes each full-size frame fully replace the previous one.
            var fctl: [UInt8] = []
            appendBigEndian(sequence, to: &fctl)
            sequence += 1
            appendBigEndian(UInt32(width), to: &fctl)
            appendBigEndian(UInt32(height), to: &fctl)
            appendBigEndian(0, to: &fctl) // x offset
            appendBigEndian(0, to: &fctl) // y offset
            fctl.append(UInt8(delayNumerator >> 8))
            fctl.append(UInt8(delayNumerator & 0xFF))
            fctl.append(UInt8(delayDenominator >> 8))
            fctl.append(UInt8(delayDenominator & 0xFF))
            fctl.append(1) // dispose_op: background
            fctl.append(0) // blend_op: source
            appendChunk(type: "fcTL", data: fctl, to: &png)

            let frameData = zlib(rawScanlines(frame))
            if index == 0 {
                // The default image doubles as the first frame.
                appendChunk(type: "IDAT", data: frameData, to: &png)
            } else {
                var fdat: [UInt8] = []
                appendBigEndian(sequence, to: &fdat)
                sequence += 1
                fdat.append(contentsOf: frameData)
                appendChunk(type: "fdAT", data: fdat, to: &png)
            }
        }

        appendChunk(type: "IEND", data: [], to: &png)
        return png
    }

    // MARK: - Building Blocks

    /// The IHDR chunk body for an 8-bit RGBA image.
    private static func ihdr(width: Int, height: Int) -> [UInt8] {
        var ihdr: [UInt8] = []
        appendBigEndian(UInt32(width), to: &ihdr)
        appendBigEndian(UInt32(height), to: &ihdr)
        ihdr.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit, RGBA, deflate, filter method 0, no interlace
        return ihdr
    }

    /// The filtered RGBA scanlines for an image. Each row picks the PNG filter (None, Sub, Up,
    /// Average, Paeth) that minimizes the sum of absolute signed residuals, the standard heuristic
    /// (RFC 2083 §9.6): decorrelating each row from its neighbors makes the DEFLATE stream far
    /// smaller. PureDraw's decoder reverses every filter type, so the output round-trips exactly.
    private static func rawScanlines(_ image: Image) -> [UInt8] {
        let bytesPerPixel = 4
        let rowBytes = image.width * bytesPerPixel
        var raw: [UInt8] = []
        raw.reserveCapacity(image.height * (1 + rowBytes))
        var previous = [UInt8](repeating: 0, count: rowBytes) // reconstructed row above; zeros above row 0
        var current = [UInt8](repeating: 0, count: rowBytes)
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let color = image.pixelColor(x: x, y: y)
                let offset = x * bytesPerPixel
                current[offset] = channelByte(color.red)
                current[offset + 1] = channelByte(color.green)
                current[offset + 2] = channelByte(color.blue)
                current[offset + 3] = channelByte(color.alpha)
            }
            let (filterType, filtered) = bestFilter(current, above: previous, bytesPerPixel: bytesPerPixel)
            raw.append(filterType)
            raw.append(contentsOf: filtered)
            swap(&previous, &current) // the original (unfiltered) row becomes the row above
        }
        return raw
    }

    /// Picks the filter type whose residuals minimize the sum-of-absolute-signed-values heuristic.
    private static func bestFilter(_ row: [UInt8], above: [UInt8], bytesPerPixel: Int) -> (type: UInt8, bytes: [UInt8]) {
        var bestType: UInt8 = 0
        var bestBytes = filterScanline(0, row, above, bytesPerPixel)
        var bestScore = filterScore(bestBytes)
        for type in 1 ... 4 {
            let candidate = filterScanline(type, row, above, bytesPerPixel)
            let score = filterScore(candidate)
            if score < bestScore {
                bestScore = score
                bestType = UInt8(type)
                bestBytes = candidate
            }
        }
        return (bestType, bestBytes)
    }

    /// Each byte's magnitude as a signed value, so residuals near 0 or 255 (i.e. -1) score low.
    private static func filterScore(_ bytes: [UInt8]) -> Int {
        var total = 0
        for byte in bytes {
            total += Int(Int8(bitPattern: byte).magnitude)
        }
        return total
    }

    /// Applies one PNG scanline filter (RFC 2083 §6) using original (reconstructed-equivalent) bytes,
    /// exactly the operation the decoder inverts.
    private static func filterScanline(_ type: Int, _ row: [UInt8], _ above: [UInt8], _ bpp: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: row.count)
        for i in 0 ..< row.count {
            let a = i >= bpp ? Int(row[i - bpp]) : 0 // left
            let b = Int(above[i]) // up
            let c = i >= bpp ? Int(above[i - bpp]) : 0 // upper-left
            let predictor: Int = switch type {
            case 1: a
            case 2: b
            case 3: (a + b) / 2
            case 4: paethPredictor(a, b, c)
            default: 0 // None
            }
            out[i] = UInt8((Int(row[i]) - predictor) & 0xFF)
        }
        return out
    }

    private static func paethPredictor(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb, pa <= pc { return a }
        return pb <= pc ? b : c
    }

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

    /// Wraps raw bytes in a valid zlib stream, DEFLATE-compressed via ``Deflate`` (falling back to
    /// stored blocks when a region does not compress). Usable both for PNG IDAT and as a PDF
    /// FlateDecode stream.
    static func zlib(_ raw: [UInt8]) -> [UInt8] {
        var stream: [UInt8] = [0x78, 0x01] // deflate, 32K window, no preset dictionary
        stream.append(contentsOf: Deflate.compressed(raw))
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
