//
//  PNGDecoder.swift
//  PureDraw
//

/// Decodes encoded image bytes into a raw-RGBA `Image`, the counterpart to `PNGEncoder`
/// (PureDraw #103). Supports PNG (8-bit grayscale, RGB, RGBA, grayscale+alpha, and palette)
/// and `data:` URIs wrapping a base64 PNG. JPEG and uncommon PNG variants (16-bit, interlaced)
/// are reported as unsupported rather than guessed, so a caller knows decoding did not happen.
public enum ImageDecoder {
    /// Why decoding failed: an unhandled format, or recognized bytes that are malformed.
    public enum Error: Swift.Error, Equatable {
        /// The bytes are not a format this decoder handles (e.g. JPEG).
        case unsupportedFormat(String)
        /// The bytes are the right format but malformed or truncated.
        case malformed(String)
    }

    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    /// Decodes encoded image bytes, sniffing the format from the leading signature.
    public static func decode(_ data: [UInt8]) throws -> Image {
        if data.count >= 8, Array(data[0 ..< 8]) == pngSignature {
            return try decodePNG(data)
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 {
            throw Error.unsupportedFormat("JPEG decoding is not implemented; decode it with a platform codec and supply raw pixels")
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
                guard data[bodyStart + 12] == 0 else { throw Error.unsupportedFormat("interlaced PNG") }
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
        guard bitDepth == 8 else { throw Error.unsupportedFormat("only 8-bit PNG is supported (got \(bitDepth)-bit)") }
        let channels: Int
        switch colorType {
        case 0: channels = 1 // grayscale
        case 2: channels = 3 // RGB
        case 3: channels = 1 // palette index
        case 4: channels = 2 // grayscale + alpha
        case 6: channels = 4 // RGBA
        default: throw Error.unsupportedFormat("PNG color type \(colorType)")
        }
        guard let raw = Inflate.zlib(idat) else { throw Error.malformed("IDAT is not a valid zlib stream") }

        let unfiltered = try unfilter(raw, width: width, height: height, bytesPerPixel: channels)
        let rgba = try assembleRGBA(unfiltered, width: width, height: height, colorType: colorType, channels: channels, palette: palette)
        do {
            return try Image(width: width, height: height, alphaInfo: .last, data: rgba)
        } catch {
            throw Error.malformed("decoded pixel buffer does not match the declared size")
        }
    }

    /// Reverses the PNG scanline filters (RFC 2083 §6): each row is prefixed with a filter
    /// type byte, then `width * bytesPerPixel` filtered bytes reconstructed against the row
    /// above and the pixel to the left.
    private static func unfilter(_ raw: [UInt8], width: Int, height: Int, bytesPerPixel bpp: Int) throws -> [UInt8] {
        let rowBytes = width * bpp
        guard raw.count >= height * (rowBytes + 1) else { throw Error.malformed("IDAT shorter than the declared image") }
        var out = [UInt8](repeating: 0, count: height * rowBytes)
        for row in 0 ..< height {
            let filter = raw[row * (rowBytes + 1)]
            let srcStart = row * (rowBytes + 1) + 1
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
