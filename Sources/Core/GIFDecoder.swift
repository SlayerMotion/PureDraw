//
//  GIFDecoder.swift
//  PureDraw
//

/// Decodes a GIF (87a or 89a) into a raw-RGBA `Image`, invoked from `ImageDecoder.decode` when the
/// leading bytes are the GIF signature. Decodes the first image frame composited onto the logical
/// screen (the single still image a `CGImageSource` returns), honoring the global or local color
/// table, the transparent-color index, and interlacing. Animation beyond the first frame and the
/// plain-text extension are ignored; a malformed file throws `ImageDecoder.Error` rather than
/// guessing.
enum GIFDecoder {
    /// Upper bound on `width * height` (64 megapixels), bounding the RGBA and index allocations a
    /// crafted header can request.
    private static let maxPixels = 64_000_000

    static func decode(_ data: [UInt8]) throws -> Image {
        guard data.count >= 13 else { throw malformed("truncated GIF header") }
        let signature = Array(data[0 ..< 6])
        guard signature == Array("GIF87a".utf8) || signature == Array("GIF89a".utf8) else {
            throw unsupported("not a GIF")
        }

        let screenWidth = le16(data, 6)
        let screenHeight = le16(data, 8)
        guard screenWidth > 0, screenHeight > 0, screenWidth * screenHeight <= maxPixels else {
            throw unsupported("GIF dimensions too large (\(screenWidth)x\(screenHeight))")
        }

        let packed = Int(data[10])
        var pos = 13
        var globalColorTable: [UInt8] = []
        if packed & 0x80 != 0 {
            let entries = 1 << ((packed & 0x07) + 1)
            let bytes = entries * 3
            guard pos + bytes <= data.count else { throw malformed("truncated global color table") }
            globalColorTable = Array(data[pos ..< pos + bytes])
            pos += bytes
        }

        var transparentIndex: Int? = nil

        // Walk blocks until the first image descriptor. A graphic-control extension before it carries
        // the transparency flag for that image; other extensions are skipped.
        while pos < data.count {
            let blockType = data[pos]
            pos += 1
            switch blockType {
            case 0x2C: // image descriptor
                return try decodeFrame(
                    data,
                    from: pos,
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                    globalColorTable: globalColorTable,
                    transparentIndex: transparentIndex
                )
            case 0x21: // extension
                guard pos < data.count else { throw malformed("truncated extension") }
                let label = data[pos]
                pos += 1
                if label == 0xF9 { // graphic control extension
                    guard pos < data.count else { throw malformed("truncated graphic control") }
                    let size = Int(data[pos])
                    guard size == 4, pos + 1 + size <= data.count else { throw malformed("bad graphic control") }
                    if data[pos + 1] & 0x01 != 0 { transparentIndex = Int(data[pos + 4]) }
                    pos += 1 + size
                }
                // Skip remaining sub-blocks: the GCE's block terminator, or the whole body of any
                // other extension.
                pos = try skipSubBlocks(data, from: pos)
            case 0x3B: // trailer
                throw malformed("GIF has no image")
            default:
                throw malformed("unknown GIF block 0x\(hex(blockType))")
            }
        }
        throw malformed("GIF has no image descriptor")
    }

    // MARK: - Frame

    private static func decodeFrame(
        _ data: [UInt8],
        from start: Int,
        screenWidth: Int,
        screenHeight: Int,
        globalColorTable: [UInt8],
        transparentIndex: Int?
    ) throws -> Image {
        var pos = start
        guard pos + 9 <= data.count else { throw malformed("truncated image descriptor") }
        let left = le16(data, pos)
        let top = le16(data, pos + 2)
        let frameWidth = le16(data, pos + 4)
        let frameHeight = le16(data, pos + 6)
        let packed = Int(data[pos + 8])
        pos += 9
        let interlaced = packed & 0x40 != 0

        var colorTable = globalColorTable
        if packed & 0x80 != 0 { // local color table
            let entries = 1 << ((packed & 0x07) + 1)
            let bytes = entries * 3
            guard pos + bytes <= data.count else { throw malformed("truncated local color table") }
            colorTable = Array(data[pos ..< pos + bytes])
            pos += bytes
        }
        guard !colorTable.isEmpty else { throw malformed("GIF frame has no color table") }
        guard frameWidth > 0, frameHeight > 0, frameWidth * frameHeight <= maxPixels else {
            throw malformed("invalid GIF frame size")
        }

        guard pos < data.count else { throw malformed("missing LZW data") }
        let minCodeSize = Int(data[pos])
        pos += 1
        guard minCodeSize >= 2, minCodeSize <= 8 else { throw malformed("invalid LZW minimum code size") }

        var lzw: [UInt8] = []
        pos = try collectSubBlocks(data, from: pos, into: &lzw)

        let indices = try decodeLZW(lzw, minCodeSize: minCodeSize, count: frameWidth * frameHeight)
        let pixels = interlaced ? deinterlace(indices, width: frameWidth, height: frameHeight) : indices

        // Composite the frame onto a transparent logical screen.
        var rgba = [UInt8](repeating: 0, count: screenWidth * screenHeight * 4)
        let paletteCount = colorTable.count / 3
        for y in 0 ..< frameHeight {
            let sy = top + y
            guard sy < screenHeight else { break }
            for x in 0 ..< frameWidth {
                let sx = left + x
                guard sx < screenWidth else { continue }
                let index = Int(pixels[y * frameWidth + x])
                if let transparent = transparentIndex, transparent == index { continue }
                // An index past the color table is a spec violation. CoreGraphics renders such files
                // but with undefined, unreplicable colors (no clamp/wrap rule), so matching it is not
                // possible; we throw rather than emit silently-wrong pixels.
                guard index < paletteCount else { throw malformed("palette index out of range") }
                let src = index * 3
                let dst = (sy * screenWidth + sx) * 4
                rgba[dst] = colorTable[src]
                rgba[dst + 1] = colorTable[src + 1]
                rgba[dst + 2] = colorTable[src + 2]
                rgba[dst + 3] = 255
            }
        }

        do {
            return try Image(width: screenWidth, height: screenHeight, alphaInfo: .last, data: rgba)
        } catch {
            throw malformed("decoded pixel buffer does not match the declared size")
        }
    }

    // MARK: - LZW

    /// Decodes GIF's variable-width LZW (codes packed least-significant-bit first) into `count`
    /// palette indices, using the classic prefix/suffix table with an output stack.
    private static func decodeLZW(_ data: [UInt8], minCodeSize: Int, count: Int) throws -> [UInt8] {
        let clearCode = 1 << minCodeSize
        let endCode = clearCode + 1
        var codeSize = minCodeSize + 1
        var next = endCode + 1 // next free dictionary slot

        var prefix = [Int](repeating: 0, count: 4096)
        var suffix = [UInt8](repeating: 0, count: 4096)
        var stack = [UInt8](repeating: 0, count: 4096)

        var output = [UInt8]()
        output.reserveCapacity(count)

        var bitPosition = 0
        func readCode() -> Int? {
            var code = 0
            for i in 0 ..< codeSize {
                let byteIndex = bitPosition >> 3
                if byteIndex >= data.count { return nil }
                code |= ((Int(data[byteIndex]) >> (bitPosition & 7)) & 1) << i
                bitPosition += 1
            }
            return code
        }

        var previousCode = -1
        var firstByte: UInt8 = 0

        while let code = readCode() {
            if code == clearCode {
                codeSize = minCodeSize + 1
                next = endCode + 1
                previousCode = -1
                continue
            }
            if code == endCode { break }

            if previousCode == -1 {
                // First code after a clear must be a literal; it seeds the chain.
                guard code < clearCode else { throw malformed("invalid first LZW code") }
                output.append(UInt8(code))
                firstByte = UInt8(code)
                previousCode = code
                continue
            }

            var stackTop = 0
            var current = code
            if code >= next {
                // The not-yet-defined-code (KwKwK) case: emit the previous string plus its first byte.
                guard code == next else { throw malformed("invalid LZW code") }
                stack[stackTop] = firstByte
                stackTop += 1
                current = previousCode
            }
            // Walk the prefix chain, pushing suffixes (reverses the string).
            while current >= clearCode {
                guard current < 4096 else { throw malformed("corrupt LZW chain") }
                stack[stackTop] = suffix[current]
                stackTop += 1
                current = prefix[current]
            }
            firstByte = UInt8(current)
            stack[stackTop] = firstByte
            stackTop += 1
            while stackTop > 0 {
                stackTop -= 1
                output.append(stack[stackTop])
            }

            // Add previousString + firstByte as the new dictionary entry.
            if next < 4096 {
                prefix[next] = previousCode
                suffix[next] = firstByte
                next += 1
                if next == (1 << codeSize), codeSize < 12 { codeSize += 1 }
            }
            previousCode = code
        }

        // A complete frame yields exactly `count` indices. Fewer means the stream was truncated:
        // throw rather than zero-pad a guessed image. A few extra (a final code that overruns the
        // frame) are dropped, matching lenient decoders.
        guard output.count >= count else { throw malformed("truncated GIF image data") }
        if output.count > count { output.removeLast(output.count - count) }
        return output
    }

    // MARK: - Helpers

    /// Reorders the four interlace passes (rows starting at 0, 4, 2, 1 with strides 8, 8, 4, 2) into
    /// sequential rows.
    private static func deinterlace(_ source: [UInt8], width: Int, height: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: source.count)
        var sourceRow = 0
        let passes: [(start: Int, step: Int)] = [(0, 8), (4, 8), (2, 4), (1, 2)]
        for pass in passes {
            var y = pass.start
            while y < height {
                let src = sourceRow * width
                let dst = y * width
                for x in 0 ..< width {
                    out[dst + x] = source[src + x]
                }
                sourceRow += 1
                y += pass.step
            }
        }
        return out
    }

    /// Concatenates a chain of length-prefixed sub-blocks into `buffer`, returning the position after
    /// the terminating zero-length block.
    private static func collectSubBlocks(_ data: [UInt8], from start: Int, into buffer: inout [UInt8]) throws -> Int {
        var pos = start
        while pos < data.count {
            let length = Int(data[pos])
            pos += 1
            if length == 0 { return pos }
            guard pos + length <= data.count else { throw malformed("truncated sub-block") }
            buffer.append(contentsOf: data[pos ..< pos + length])
            pos += length
        }
        throw malformed("unterminated sub-blocks")
    }

    /// Skips a chain of length-prefixed sub-blocks, returning the position after the terminator.
    private static func skipSubBlocks(_ data: [UInt8], from start: Int) throws -> Int {
        var pos = start
        while pos < data.count {
            let length = Int(data[pos])
            pos += 1
            if length == 0 { return pos }
            guard pos + length <= data.count else { throw malformed("truncated sub-block") }
            pos += length
        }
        throw malformed("unterminated sub-blocks")
    }

    private static func le16(_ data: [UInt8], _ offset: Int) -> Int {
        Int(data[offset]) | Int(data[offset + 1]) << 8
    }

    private static func hex(_ byte: UInt8) -> String {
        let digits = Array("0123456789ABCDEF")
        return String([digits[Int(byte) >> 4], digits[Int(byte) & 0x0F]])
    }

    private static func malformed(_ message: String) -> ImageDecoder.Error {
        .malformed(message)
    }

    private static func unsupported(_ message: String) -> ImageDecoder.Error {
        .unsupportedFormat(message)
    }
}
