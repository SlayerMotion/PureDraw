//
//  PNGDecoder.swift
//  PureDraw
//

/// Decodes encoded image bytes into a raw-RGBA `Image`, the counterpart to `PNGEncoder`
/// (PureDraw #103). Supports PNG (grayscale, RGB, RGBA, grayscale+alpha, and palette at every valid
/// bit depth 1/2/4/8/16, including Adam7 interlacing), JPEG (baseline, extended-sequential, and
/// progressive; see `JPEGDecoder`), GIF (87a/89a, first frame; see `GIFDecoder`), and `data:` URIs
/// wrapping any of them. Non-supported JPEG (arithmetic, 12-bit, CMYK) is reported as unsupported
/// rather than guessed, so a caller knows decoding did not happen.
public enum ImageDecoder {
    /// Why decoding failed: an unhandled format, or recognized bytes that are malformed.
    public enum Error: Swift.Error, Equatable {
        /// The bytes are not a format this decoder handles (e.g. JPEG).
        case unsupportedFormat(String)
        /// The bytes are the right format but malformed or truncated.
        case malformed(String)
    }

    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    /// Upper bound on a PNG's pixel count, 64 megapixels, bounding the sample and RGBA allocations a
    /// crafted IHDR can request. Matches the JPEG and GIF decoders.
    private static let maxPixels = 64_000_000
    /// Per-axis cap (16 mebipixels) so a row's bit count `width * bitsPerPixel` cannot overflow a
    /// 32-bit `Int` on the WASM target (16M x 64 bpp stays under 2^31). This is far above any real
    /// image yet permits long/thin PNGs the pixel cap alone would allow, unlike JPEG's 16-bit limit.
    private static let maxDimension = 16_777_216

    /// Decodes encoded image bytes, sniffing the format from the leading signature.
    public static func decode(_ data: [UInt8]) throws -> Image {
        if data.count >= 8, Array(data[0 ..< 8]) == pngSignature {
            return try decodePNG(data)
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 {
            return try JPEGDecoder.decode(data)
        }
        if data.count >= 6, data[0] == 0x47, data[1] == 0x49, data[2] == 0x46 { // "GIF"
            return try GIFDecoder.decode(data)
        }
        throw Error.unsupportedFormat("unrecognized image signature")
    }

    /// Decodes a `data:` URI (`data:[<mediatype>][;base64],<payload>`). Only base64 payloads
    /// are supported (raw percent-encoded payloads are not image data in practice).
    public static func decode(dataURI: String) throws -> Image {
        guard dataURI.hasPrefix("data:"), let comma = dataURI.firstIndex(of: ",") else {
            throw Error.malformed("not a data URI")
        }
        let meta = dataURI[dataURI.index(dataURI.startIndex, offsetBy: 5) ..< comma]
        guard meta.contains("base64") else {
            throw Error.unsupportedFormat("only base64 data URIs are supported")
        }
        let payload = String(dataURI[dataURI.index(after: comma)...])
        guard let bytes = base64Decode(payload) else { throw Error.malformed("invalid base64 payload") }
        return try decode(bytes)
    }

    // MARK: - PNG

    private static func decodePNG(_ data: [UInt8]) throws -> Image {
        var idat: [UInt8] = []
        var width = 0, height = 0, bitDepth = 0, colorType = 0
        var interlaced = false
        var palette: [UInt8] = []

        var pos = 8 // after the signature
        while pos + 8 <= data.count {
            let length = beUInt32(data, pos)
            let type = String(decoding: data[pos + 4 ..< pos + 8], as: UTF8.self)
            let bodyStart = pos + 8
            let bodyEnd = bodyStart + length
            guard bodyEnd + 4 <= data.count else { throw Error.malformed("chunk \(type) overruns the file") }
            let body = data[bodyStart ..< bodyEnd]

            switch type {
            case "IHDR":
                guard length == 13 else { throw Error.malformed("IHDR is not 13 bytes") }
                width = beUInt32(data, bodyStart)
                height = beUInt32(data, bodyStart + 4)
                bitDepth = Int(data[bodyStart + 8])
                colorType = Int(data[bodyStart + 9])
                let interlaceMethod = Int(data[bodyStart + 12])
                guard interlaceMethod == 0 || interlaceMethod == 1 else {
                    throw Error.unsupportedFormat("PNG interlace method \(interlaceMethod)")
                }
                interlaced = interlaceMethod == 1
            case "PLTE":
                palette = Array(body)
            case "IDAT":
                idat.append(contentsOf: body)
            case "IEND":
                pos = data.count // done
                continue
            default:
                break // ancillary chunk, ignore
            }
            pos = bodyEnd + 4 // skip the trailing CRC
        }

        guard width > 0, height > 0 else { throw Error.malformed("missing or empty IHDR") }
        // IHDR width/height are untrusted 32-bit fields; bound them before any image-sized allocation
        // so a crafted header refuses rather than overflowing `Int` or exhausting memory. The product
        // is checked by division so the check itself cannot overflow on a 32-bit target.
        guard width <= maxDimension, height <= maxDimension, height <= maxPixels / width else {
            throw Error.unsupportedFormat("PNG dimensions too large (\(width)x\(height))")
        }
        let channels: Int
        switch colorType {
        case 0: channels = 1 // grayscale
        case 2: channels = 3 // RGB
        case 3: channels = 1 // palette index
        case 4: channels = 2 // grayscale + alpha
        case 6: channels = 4 // RGBA
        default: throw Error.unsupportedFormat("PNG color type \(colorType)")
        }
        guard isValidBitDepth(bitDepth, colorType: colorType) else {
            throw Error.unsupportedFormat("PNG bit depth \(bitDepth) is invalid for color type \(colorType)")
        }
        guard let raw = Inflate.zlib(idat) else { throw Error.malformed("IDAT is not a valid zlib stream") }

        // Reconstruct one 8-bit sample per channel, handling sub-byte (1/2/4) and 16-bit depths and
        // Adam7 interlacing, then expand to RGBA.
        let samples = try reconstructSamples(raw, width: width, height: height, bitDepth: bitDepth, channels: channels, isPaletteIndex: colorType == 3, interlaced: interlaced)
        let rgba = try assembleRGBA(samples, width: width, height: height, colorType: colorType, channels: channels, palette: palette)
        do {
            return try Image(width: width, height: height, alphaInfo: .last, data: rgba)
        } catch {
            throw Error.malformed("decoded pixel buffer does not match the declared size")
        }
    }

    /// Whether `bitDepth` is one the PNG spec allows for `colorType`.
    private static func isValidBitDepth(_ bitDepth: Int, colorType: Int) -> Bool {
        switch colorType {
        case 0: [1, 2, 4, 8, 16].contains(bitDepth) // grayscale
        case 3: [1, 2, 4, 8].contains(bitDepth) // palette (no 16-bit indices)
        case 2, 4, 6: [8, 16].contains(bitDepth) // truecolour and alpha variants
        default: false
        }
    }

    /// The seven Adam7 interlace passes as (xStart, yStart, xStep, yStep). A non-interlaced image is
    /// decoded as a single full-image pass and does not use this table.
    private static let adam7Passes: [(xStart: Int, yStart: Int, xStep: Int, yStep: Int)] = [
        (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2),
    ]

    /// Reconstructs one 8-bit sample per channel for the whole image. A non-interlaced image is a
    /// single full-image pass returned directly; an interlaced image's seven Adam7 passes are each
    /// unfiltered and bit-unpacked independently, then scattered to their interlaced positions.
    private static func reconstructSamples(
        _ raw: [UInt8],
        width: Int,
        height: Int,
        bitDepth: Int,
        channels: Int,
        isPaletteIndex: Bool,
        interlaced: Bool
    ) throws -> [UInt8] {
        let bitsPerPixel = channels * bitDepth
        let bytesPerPixel = max(1, (bitsPerPixel + 7) / 8) // filter distance, per RFC 2083

        /// Unfilters and bit-unpacks one sub-image (a pass, or the whole image) starting at `offset`.
        func decodePass(width passWidth: Int, height passHeight: Int, offset: Int) throws -> (samples: [UInt8], nextOffset: Int) {
            let rowBytes = (passWidth * bitsPerPixel + 7) / 8
            let (filtered, next) = try unfilter(raw, offset: offset, rowBytes: rowBytes, height: passHeight, bytesPerPixel: bytesPerPixel)
            let unpacked = unpackSamples(filtered, width: passWidth, height: passHeight, bitDepth: bitDepth, channels: channels, isPaletteIndex: isPaletteIndex, rowBytes: rowBytes)
            return (unpacked, next)
        }

        // The common case: one pass laid out exactly as the output, so no scatter copy is needed.
        guard interlaced else {
            return try decodePass(width: width, height: height, offset: 0).samples
        }

        var samples = [UInt8](repeating: 0, count: width * height * channels)
        var offset = 0
        for pass in adam7Passes {
            let passWidth = (width - pass.xStart + pass.xStep - 1) / pass.xStep
            let passHeight = (height - pass.yStart + pass.yStep - 1) / pass.yStep
            guard passWidth > 0, passHeight > 0 else { continue }

            let (passSamples, next) = try decodePass(width: passWidth, height: passHeight, offset: offset)
            offset = next
            for row in 0 ..< passHeight {
                let destinationY = pass.yStart + row * pass.yStep
                for col in 0 ..< passWidth {
                    let destinationX = pass.xStart + col * pass.xStep
                    let source = (row * passWidth + col) * channels
                    let destination = (destinationY * width + destinationX) * channels
                    for channel in 0 ..< channels {
                        samples[destination + channel] = passSamples[source + channel]
                    }
                }
            }
        }
        return samples
    }

    /// Reverses the PNG scanline filters (RFC 2083 §6) for `height` rows of `rowBytes` filtered bytes
    /// each starting at `offset`. Each row is prefixed by a filter-type byte and reconstructed against
    /// the row above and the pixel `bytesPerPixel` to the left. Returns the bytes and the offset past
    /// the consumed rows (so interlaced passes can be read back to back).
    private static func unfilter(_ raw: [UInt8], offset: Int, rowBytes: Int, height: Int, bytesPerPixel bpp: Int) throws -> (bytes: [UInt8], nextOffset: Int) {
        let needed = height * (rowBytes + 1)
        guard offset + needed <= raw.count else { throw Error.malformed("IDAT shorter than the declared image") }
        var out = [UInt8](repeating: 0, count: height * rowBytes)
        for row in 0 ..< height {
            let filter = raw[offset + row * (rowBytes + 1)]
            let srcStart = offset + row * (rowBytes + 1) + 1
            let dstStart = row * rowBytes
            for i in 0 ..< rowBytes {
                let x = Int(raw[srcStart + i])
                let a = i >= bpp ? Int(out[dstStart + i - bpp]) : 0 // left
                let b = row > 0 ? Int(out[dstStart - rowBytes + i]) : 0 // above
                let c = (row > 0 && i >= bpp) ? Int(out[dstStart - rowBytes + i - bpp]) : 0 // upper-left
                let recon: Int
                switch filter {
                case 0: recon = x
                case 1: recon = x + a
                case 2: recon = x + b
                case 3: recon = x + (a + b) / 2
                case 4: recon = x + paeth(a, b, c)
                default: throw Error.malformed("unknown scanline filter \(filter)")
                }
                out[dstStart + i] = UInt8(recon & 0xFF)
            }
        }
        return (out, offset + needed)
    }

    /// Expands bit-packed filtered scanlines into one 8-bit sample per channel. 16-bit samples are
    /// scaled down to 8-bit with rounding; sub-byte (1/2/4) grayscale samples are scaled to the full
    /// 0...255 range, while palette indices are kept as the raw index value.
    private static func unpackSamples(_ filtered: [UInt8], width: Int, height: Int, bitDepth: Int, channels: Int, isPaletteIndex: Bool, rowBytes: Int) -> [UInt8] {
        let perRow = width * channels
        var out = [UInt8](repeating: 0, count: width * height * channels)
        for row in 0 ..< height {
            let rowStart = row * rowBytes
            let outStart = row * perRow
            switch bitDepth {
            case 16:
                // Big-endian 16-bit sample scaled to 8-bit with rounding (matching CoreGraphics),
                // not a high-byte truncation.
                for s in 0 ..< perRow {
                    let value = Int(filtered[rowStart + s * 2]) << 8 | Int(filtered[rowStart + s * 2 + 1])
                    out[outStart + s] = UInt8((value * 255 + 32767) / 65535)
                }
            case 8:
                for s in 0 ..< perRow {
                    out[outStart + s] = filtered[rowStart + s]
                }
            default: // 1, 2, 4: MSB-first within each byte; rows are byte-aligned (bit position resets)
                let maxValue = (1 << bitDepth) - 1
                var bitPosition = 0
                for s in 0 ..< perRow {
                    let byteIndex = rowStart + (bitPosition >> 3)
                    let shift = 8 - bitDepth - (bitPosition & 7)
                    let value = (Int(filtered[byteIndex]) >> shift) & maxValue
                    bitPosition += bitDepth
                    out[outStart + s] = isPaletteIndex ? UInt8(value) : UInt8(value * 255 / maxValue)
                }
            }
        }
        return out
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb, pa <= pc { return a }
        return pb <= pc ? b : c
    }

    /// Expands the unfiltered samples into a straight-alpha RGBA buffer for the color type.
    private static func assembleRGBA(_ s: [UInt8], width: Int, height: Int, colorType: Int, channels: Int, palette: [UInt8]) throws -> [UInt8] {
        let count = width * height
        var rgba = [UInt8](repeating: 0, count: count * 4)
        for i in 0 ..< count {
            let src = i * channels, dst = i * 4
            switch colorType {
            case 0: // grayscale
                let g = s[src]
                rgba[dst] = g
                rgba[dst + 1] = g
                rgba[dst + 2] = g
                rgba[dst + 3] = 255
            case 2: // RGB
                rgba[dst] = s[src]
                rgba[dst + 1] = s[src + 1]
                rgba[dst + 2] = s[src + 2]
                rgba[dst + 3] = 255
            case 3: // palette index
                let p = Int(s[src]) * 3
                guard p + 2 < palette.count else { throw Error.malformed("palette index out of range") }
                rgba[dst] = palette[p]
                rgba[dst + 1] = palette[p + 1]
                rgba[dst + 2] = palette[p + 2]
                rgba[dst + 3] = 255
            case 4: // grayscale + alpha
                let g = s[src]
                rgba[dst] = g
                rgba[dst + 1] = g
                rgba[dst + 2] = g
                rgba[dst + 3] = s[src + 1]
            default: // 6: RGBA
                rgba[dst] = s[src]
                rgba[dst + 1] = s[src + 1]
                rgba[dst + 2] = s[src + 2]
                rgba[dst + 3] = s[src + 3]
            }
        }
        return rgba
    }

    private static func beUInt32(_ data: [UInt8], _ offset: Int) -> Int {
        Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
    }

    // MARK: - base64 (dependency-free; Core has no Foundation)

    private static let base64Alphabet: [Character: Int] = {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        return Dictionary(uniqueKeysWithValues: chars.enumerated().map { ($1, $0) })
    }()

    static func base64Decode(_ string: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        var accum = 0, bits = 0
        for ch in string {
            if ch == "=" || ch == "\n" || ch == "\r" || ch == " " { continue }
            guard let v = base64Alphabet[ch] else { return nil }
            accum = accum << 6 | v
            bits += 6
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((accum >> bits) & 0xFF))
            }
        }
        return bytes
    }
}
