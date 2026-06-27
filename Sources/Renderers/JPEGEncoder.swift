//
//  JPEGEncoder.swift
//  PureDraw
//

import Core

/// Encodes an `Image` into a baseline (sequential, Huffman) JPEG/JFIF, the counterpart to
/// `JPEGDecoder`. Output is a standards-conformant baseline file: 3-component YCbCr with 4:2:0
/// chroma subsampling by default (or full-resolution 4:4:4 on request), level-shifted forward DCT,
/// quality-scaled standard quantization tables, and **optimal** Huffman tables derived from the
/// image's own symbol statistics (the JPEG Annex K procedure) rather than the fixed example tables.
/// Alpha is dropped (JPEG has no alpha channel).
///
/// Optimal tables are used deliberately: they avoid hand-transcribing the 162-entry standard
/// tables, compress better, and are exercised end to end by the round-trip and ImageIO tests.
public enum JPEGEncoder {
    /// Chroma subsampling mode. `ratio420` (the default of most JPEG encoders) halves chroma
    /// resolution on both axes, roughly halving file size for a small chroma-fidelity cost; `none`
    /// keeps full-resolution 4:4:4 chroma.
    public enum ChromaSubsampling: Sendable {
        case full // 4:4:4
        case ratio420 // 4:2:0
    }

    /// Encodes the image at `quality` (1...100) and writes the result to a data consumer.
    public static func encode(_ image: Image, quality: Int = 90, subsampling: ChromaSubsampling = .ratio420, to consumer: DataConsumer) {
        consumer.write(encode(image, quality: quality, subsampling: subsampling))
    }

    /// Encodes an RGBA `Image` as the bytes of a baseline JPEG file. `quality` is clamped to
    /// 1...100 (higher is better and larger), matching the conventional IJG scale.
    ///
    /// Returns an empty array for dimensions JPEG cannot represent (zero, or larger than the 16-bit
    /// frame fields allow, i.e. > 65535 in either axis); callers should treat empty output as "not
    /// encoded".
    public static func encode(_ image: Image, quality: Int = 90, subsampling: ChromaSubsampling = .ratio420) -> [UInt8] {
        let width = image.width
        let height = image.height
        // JPEG frame dimensions are 16-bit fields; reject anything that would not fit rather than
        // trapping when the high byte is written.
        guard width > 0, height > 0, width <= 65535, height <= 65535 else { return [] }

        let lumaQuant = scaledQuantTable(base: baseLuminanceQuant, quality: quality)
        let chromaQuant = scaledQuantTable(base: baseChrominanceQuant, quality: quality)

        // Forward transform every component's blocks into zig-zag-ordered quantized coefficients.
        // 4:4:4 stores one 8x8 block per component per MCU; 4:2:0 stores a 2x2 grid of luma blocks
        // per 16x16 MCU against one half-resolution chroma block.
        let (yPlane, cbPlane, crPlane) = yCbCrPlanes(image, width: width, height: height)

        let mcusWide: Int, mcusHigh: Int, yCols: Int, yRows: Int, chromaCols: Int, chromaRows: Int
        let lumaSampling: UInt8
        let chromaCb: [Double], chromaCr: [Double], chromaWidth: Int, chromaHeight: Int
        switch subsampling {
        case .full:
            mcusWide = (width + 7) / 8
            mcusHigh = (height + 7) / 8
            yCols = mcusWide
            yRows = mcusHigh
            chromaCols = mcusWide
            chromaRows = mcusHigh
            lumaSampling = 0x11
            chromaCb = cbPlane
            chromaCr = crPlane
            chromaWidth = width
            chromaHeight = height
        case .ratio420:
            mcusWide = (width + 15) / 16
            mcusHigh = (height + 15) / 16
            yCols = mcusWide * 2
            yRows = mcusHigh * 2
            chromaCols = mcusWide
            chromaRows = mcusHigh
            lumaSampling = 0x22
            let cb = downsampleChroma(cbPlane, width: width, height: height)
            let cr = downsampleChroma(crPlane, width: width, height: height)
            chromaCb = cb.plane
            chromaCr = cr.plane
            chromaWidth = cb.width
            chromaHeight = cb.height
        }

        // Scratch buffers reused across every block of the forward transform.
        var samples = [Double](repeating: 0, count: 64)
        var intermediate = [Double](repeating: 0, count: 64)
        var natural = [Int](repeating: 0, count: 64)
        let yBlocks = gatherBlocks(
            yPlane,
            planeWidth: width,
            planeHeight: height,
            cols: yCols,
            rows: yRows,
            quant: lumaQuant,
            samples: &samples,
            intermediate: &intermediate,
            natural: &natural
        )
        let cbBlocks = gatherBlocks(
            chromaCb,
            planeWidth: chromaWidth,
            planeHeight: chromaHeight,
            cols: chromaCols,
            rows: chromaRows,
            quant: chromaQuant,
            samples: &samples,
            intermediate: &intermediate,
            natural: &natural
        )
        let crBlocks = gatherBlocks(
            chromaCr,
            planeWidth: chromaWidth,
            planeHeight: chromaHeight,
            cols: chromaCols,
            rows: chromaRows,
            quant: chromaQuant,
            samples: &samples,
            intermediate: &intermediate,
            natural: &natural
        )

        // Reorder luma blocks from the raster grid into MCU scan order (for 4:2:0 the 2x2 luma
        // blocks of each MCU become contiguous). DC coefficients are differentially predicted in
        // scan order, so the frequency tally and the entropy encode MUST walk the blocks in the same
        // order or they build mismatched DC tables and emit codes the decoder cannot read. (For
        // 4:4:4, where each MCU is a single block, this is the identity reordering.)
        let lumaPerAxis = yCols == mcusWide ? 1 : 2
        var yScan: [[Int]] = []
        yScan.reserveCapacity(yBlocks.count)
        for my in 0 ..< mcusHigh {
            for mx in 0 ..< mcusWide {
                for dy in 0 ..< lumaPerAxis {
                    for dx in 0 ..< lumaPerAxis {
                        yScan.append(yBlocks[(my * lumaPerAxis + dy) * yCols + (mx * lumaPerAxis + dx)])
                    }
                }
            }
        }

        // Pass 1: tally symbol frequencies, separately for luma and chroma DC/AC, and build an
        // optimal Huffman table for each.
        var dcLumaFreq = [Int](repeating: 0, count: 257)
        var acLumaFreq = [Int](repeating: 0, count: 257)
        var dcChromaFreq = [Int](repeating: 0, count: 257)
        var acChromaFreq = [Int](repeating: 0, count: 257)
        tally(yScan, dc: &dcLumaFreq, ac: &acLumaFreq)
        tally(cbBlocks, dc: &dcChromaFreq, ac: &acChromaFreq)
        tally(crBlocks, dc: &dcChromaFreq, ac: &acChromaFreq)

        let dcLuma = HuffmanSpec(frequencies: dcLumaFreq)
        let acLuma = HuffmanSpec(frequencies: acLumaFreq)
        let dcChroma = HuffmanSpec(frequencies: dcChromaFreq)
        let acChroma = HuffmanSpec(frequencies: acChromaFreq)

        // Assemble the file.
        var out: [UInt8] = []
        out += [0xFF, 0xD8] // SOI
        appendAPP0(&out)
        appendDQT(&out, table: lumaQuant, id: 0)
        appendDQT(&out, table: chromaQuant, id: 1)
        appendSOF0(&out, width: width, height: height, lumaSampling: lumaSampling)
        appendDHT(&out, spec: dcLuma, tableClass: 0, id: 0)
        appendDHT(&out, spec: acLuma, tableClass: 1, id: 0)
        appendDHT(&out, spec: dcChroma, tableClass: 0, id: 1)
        appendDHT(&out, spec: acChroma, tableClass: 1, id: 1)
        appendSOSHeader(&out)

        // Pass 2: emit the entropy-coded scan in MCU order (the MCU's luma blocks, then Cb, Cr) with
        // per-component DC prediction. `yScan` is already in scan order, matching the tally above.
        var writer = BitWriter()
        var predY = 0, predCb = 0, predCr = 0
        let lumaPerMCU = lumaPerAxis * lumaPerAxis
        var yIndex = 0
        for my in 0 ..< mcusHigh {
            for mx in 0 ..< mcusWide {
                for _ in 0 ..< lumaPerMCU {
                    encodeBlock(yScan[yIndex], dc: dcLuma, ac: acLuma, predictor: &predY, into: &writer)
                    yIndex += 1
                }
                encodeBlock(cbBlocks[my * chromaCols + mx], dc: dcChroma, ac: acChroma, predictor: &predCb, into: &writer)
                encodeBlock(crBlocks[my * chromaCols + mx], dc: dcChroma, ac: acChroma, predictor: &predCr, into: &writer)
            }
        }
        out += writer.finish()
        out += [0xFF, 0xD9] // EOI
        return out
    }

    // MARK: - Color

    /// Builds the three full-resolution YCbCr planes from the image's RGB in a single pass (each
    /// pixel is read and unpacked once), as `Double` samples not yet level-shifted.
    private static func yCbCrPlanes(_ image: Image, width: Int, height: Int) -> (y: [Double], cb: [Double], cr: [Double]) {
        var yPlane = [Double](repeating: 0, count: width * height)
        var cbPlane = [Double](repeating: 0, count: width * height)
        var crPlane = [Double](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let color = image.pixelColor(x: x, y: y)
                let r = color.red * 255.0
                let g = color.green * 255.0
                let b = color.blue * 255.0
                let index = y * width + x
                yPlane[index] = 0.299 * r + 0.587 * g + 0.114 * b
                cbPlane[index] = -0.168736 * r - 0.331264 * g + 0.5 * b + 128.0
                crPlane[index] = 0.5 * r - 0.418688 * g - 0.081312 * b + 128.0
            }
        }
        return (yPlane, cbPlane, crPlane)
    }

    // MARK: - Forward DCT + quantization

    /// Forward-DCT and quantize the 8x8 block at (bx, by), returning its 64 coefficients in
    /// zig-zag order. Blocks straddling the right/bottom edge replicate the edge sample.
    private static func quantizedZigZag(
        _ plane: [Double],
        bx: Int,
        by: Int,
        width: Int,
        height: Int,
        quant: [Int],
        samples: inout [Double],
        intermediate: inout [Double],
        natural: inout [Int]
    ) -> [Int] {
        // Gather the (edge-clamped) block, level-shifted by -128.
        for j in 0 ..< 8 {
            let sy = min(by * 8 + j, height - 1)
            for i in 0 ..< 8 {
                let sx = min(bx * 8 + i, width - 1)
                samples[j * 8 + i] = plane[sy * width + sx] - 128.0
            }
        }

        let basis = fdctBasis
        // Vertical pass: T[v][x] = sum_y basis[v][y] * samples[y][x].
        for v in 0 ..< 8 {
            for x in 0 ..< 8 {
                var sum = 0.0
                for y in 0 ..< 8 {
                    sum += basis[v * 8 + y] * samples[y * 8 + x]
                }
                intermediate[v * 8 + x] = sum
            }
        }
        // Horizontal pass: F[v][u] = 0.25 * sum_x basis[u][x] * T[v][x], then quantize.
        for v in 0 ..< 8 {
            for u in 0 ..< 8 {
                var sum = 0.0
                for x in 0 ..< 8 {
                    sum += basis[u * 8 + x] * intermediate[v * 8 + x]
                }
                let index = v * 8 + u
                natural[index] = Int((sum * 0.25 / Double(quant[index])).rounded())
            }
        }

        // The returned block must be its own allocation: it is retained for the second pass.
        var zigzagged = [Int](repeating: 0, count: 64)
        for k in 0 ..< 64 {
            zigzagged[k] = natural[zigZag[k]]
        }
        return zigzagged
    }

    /// The standard quantization table scaled to `quality` using the conventional IJG mapping.
    private static func scaledQuantTable(base: [Int], quality: Int) -> [Int] {
        let q = min(100, max(1, quality))
        let scale = q < 50 ? 5000 / q : 200 - q * 2
        return base.map { value in
            let scaled = (value * scale + 50) / 100
            return min(255, max(1, scaled)) // baseline 8-bit: 1...255
        }
    }

    // MARK: - Entropy symbol model

    /// Bit length of a non-negative magnitude (category / "SSSS"); 0 for 0.
    private static func magnitudeCategory(_ value: Int) -> Int {
        var bits = 0
        var v = value
        while v > 0 {
            bits += 1
            v >>= 1
        }
        return bits
    }

    /// The (category, additional-bits) pair for a signed coefficient, per T.81 F.1.2.1.
    private static func coefficientBits(_ value: Int) -> (size: Int, bits: Int) {
        if value >= 0 {
            let size = magnitudeCategory(value)
            return (size, value)
        }
        let size = magnitudeCategory(-value)
        return (size, value + (1 << size) - 1)
    }

    /// Tally the DC-category and AC-(run/size) symbols a set of blocks would emit.
    private static func tally(_ blocks: [[Int]], dc: inout [Int], ac: inout [Int]) {
        var predictor = 0
        for block in blocks {
            let diff = block[0] - predictor
            predictor = block[0]
            dc[coefficientBits(diff).size] += 1

            var run = 0
            for k in 1 ..< 64 {
                if block[k] == 0 {
                    run += 1
                    continue
                }
                while run > 15 {
                    ac[0xF0] += 1 // ZRL
                    run -= 16
                }
                let size = coefficientBits(block[k]).size
                ac[(run << 4) | size] += 1
                run = 0
            }
            if run > 0 { ac[0x00] += 1 } // EOB
        }
    }

    /// Encode one block's DC and AC coefficients into the bit writer.
    private static func encodeBlock(
        _ block: [Int],
        dc: HuffmanSpec,
        ac: HuffmanSpec,
        predictor: inout Int,
        into writer: inout BitWriter
    ) {
        let diff = block[0] - predictor
        predictor = block[0]
        let dcCoded = coefficientBits(diff)
        writer.write(dc.code[dcCoded.size], bits: dc.size[dcCoded.size])
        if dcCoded.size > 0 { writer.write(dcCoded.bits, bits: dcCoded.size) }

        var run = 0
        for k in 1 ..< 64 {
            if block[k] == 0 {
                run += 1
                continue
            }
            while run > 15 {
                writer.write(ac.code[0xF0], bits: ac.size[0xF0]) // ZRL
                run -= 16
            }
            let coded = coefficientBits(block[k])
            let symbol = (run << 4) | coded.size
            writer.write(ac.code[symbol], bits: ac.size[symbol])
            writer.write(coded.bits, bits: coded.size)
            run = 0
        }
        if run > 0 { writer.write(ac.code[0x00], bits: ac.size[0x00]) } // EOB
    }

    // MARK: - Optimal Huffman tables (T.81 Annex K.2)

    /// A Huffman table built from symbol frequencies: the `BITS`/`HUFFVAL` form written into the
    /// DHT segment, plus the per-symbol (code, length) lookup used to encode.
    private struct HuffmanSpec {
        let bits: [Int] // counts of codes of each length 1...16 (index 0 unused)
        let values: [Int] // symbols, ordered by increasing code length
        let code: [Int] // per-symbol canonical code word
        let size: [Int] // per-symbol code length in bits

        init(frequencies freq: [Int]) {
            // Build code lengths by the standard frequency-merge, reserving one code so the
            // all-ones codeword is never assigned, then limit lengths to 16 bits.
            var freq = freq
            freq[256] = 1 // reserved pseudo-symbol
            var codeSize = [Int](repeating: 0, count: 257)
            var others = [Int](repeating: -1, count: 257)

            while true {
                // Two least-frequent still-live entries (ties resolve to the higher index).
                var c1 = -1
                var least = Int.max
                for i in 0 ... 256 where freq[i] > 0 && freq[i] <= least {
                    least = freq[i]
                    c1 = i
                }
                var c2 = -1
                least = Int.max
                for i in 0 ... 256 where freq[i] > 0 && freq[i] <= least && i != c1 {
                    least = freq[i]
                    c2 = i
                }
                if c2 < 0 { break }

                freq[c1] += freq[c2]
                freq[c2] = 0
                codeSize[c1] += 1
                while others[c1] >= 0 {
                    c1 = others[c1]
                    codeSize[c1] += 1
                }
                others[c1] = c2
                codeSize[c2] += 1
                while others[c2] >= 0 {
                    c2 = others[c2]
                    codeSize[c2] += 1
                }
            }

            // A degenerate frequency distribution can drive code lengths up to (symbols - 1) = 256
            // before limiting, so size the histogram for that worst case rather than assuming <= 32
            // (the unguarded write here is exactly the spot the IJG reference protects).
            var lengthCounts = [Int](repeating: 0, count: 257)
            for i in 0 ... 256 where codeSize[i] > 0 {
                lengthCounts[codeSize[i]] += 1
            }

            // Limit code lengths to 16 bits (T.81 Figure K.3), starting from the longest possible.
            var i = 256
            while i > 16 {
                while lengthCounts[i] > 0 {
                    var j = i - 2
                    while lengthCounts[j] == 0 {
                        j -= 1
                    }
                    lengthCounts[i] -= 2
                    lengthCounts[i - 1] += 1
                    lengthCounts[j + 1] += 2
                    lengthCounts[j] -= 1
                }
                i -= 1
            }

            // Remove the reserved pseudo-symbol from the longest present length.
            var last = 16
            while last > 0, lengthCounts[last] == 0 {
                last -= 1
            }
            if last > 0 { lengthCounts[last] -= 1 }

            var bits = [Int](repeating: 0, count: 17)
            for length in 1 ... 16 {
                bits[length] = lengthCounts[length]
            }
            self.bits = bits

            // HUFFVAL: real symbols (0...255) ordered by their pre-limit code length, which can run
            // up to 256 (the same worst case the histogram above is sized for). Iterating only to 32
            // would drop the longest-code symbols and desync `values` from `bits`/`huffSizes`.
            var values: [Int] = []
            for length in 1 ... 256 {
                for symbol in 0 ... 255 where codeSize[symbol] == length {
                    values.append(symbol)
                }
            }
            self.values = values

            // Canonical (code, length) per symbol.
            var code = [Int](repeating: 0, count: 256)
            var size = [Int](repeating: 0, count: 256)
            var huffSizes: [Int] = []
            for length in 1 ... 16 {
                for _ in 0 ..< bits[length] {
                    huffSizes.append(length)
                }
            }
            var nextCode = 0
            var si = huffSizes.first ?? 0
            var p = 0
            while p < huffSizes.count {
                while p < huffSizes.count, huffSizes[p] == si {
                    code[values[p]] = nextCode
                    size[values[p]] = si
                    nextCode += 1
                    p += 1
                }
                nextCode <<= 1
                si += 1
            }
            self.code = code
            self.size = size
        }
    }

    // MARK: - Segment writers

    private static func appendAPP0(_ out: inout [UInt8]) {
        // JFIF APP0: version 1.1, aspect-ratio units, 1x1 density, no thumbnail.
        out += [0xFF, 0xE0, 0x00, 0x10]
        out += [0x4A, 0x46, 0x49, 0x46, 0x00] // "JFIF\0"
        out += [0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]
    }

    private static func appendDQT(_ out: inout [UInt8], table: [Int], id: Int) {
        out += [0xFF, 0xDB, 0x00, 0x43] // length 67 = 2 + 1 + 64
        out.append(UInt8(id)) // precision 0 (8-bit) in the high nibble, table id in the low
        for k in 0 ..< 64 {
            out.append(UInt8(table[zigZag[k]])) // written in zig-zag order
        }
    }

    private static func appendSOF0(_ out: inout [UInt8], width: Int, height: Int, lumaSampling: UInt8) {
        out += [0xFF, 0xC0, 0x00, 0x11, 0x08] // length 17, precision 8
        out += [UInt8(height >> 8), UInt8(height & 0xFF)]
        out += [UInt8(width >> 8), UInt8(width & 0xFF)]
        out.append(0x03) // three components
        out += [0x01, lumaSampling, 0x00] // Y:  id 1, luma sampling (0x11=4:4:4, 0x22=4:2:0), quant table 0
        out += [0x02, 0x11, 0x01] // Cb: id 2, 1x1 sampling, quant table 1
        out += [0x03, 0x11, 0x01] // Cr: id 3, 1x1 sampling, quant table 1
    }

    /// Forward-DCTs and quantizes a `cols` x `rows` grid of 8x8 blocks from a plane (edge-clamped at
    /// the right/bottom so partial MCUs are padded, per the JPEG convention).
    private static func gatherBlocks(
        _ plane: [Double],
        planeWidth: Int,
        planeHeight: Int,
        cols: Int,
        rows: Int,
        quant: [Int],
        samples: inout [Double],
        intermediate: inout [Double],
        natural: inout [Int]
    ) -> [[Int]] {
        var blocks: [[Int]] = []
        blocks.reserveCapacity(cols * rows)
        for by in 0 ..< rows {
            for bx in 0 ..< cols {
                blocks.append(quantizedZigZag(
                    plane, bx: bx, by: by, width: planeWidth, height: planeHeight,
                    quant: quant, samples: &samples, intermediate: &intermediate, natural: &natural
                ))
            }
        }
        return blocks
    }

    /// Box-averages a full-resolution chroma plane to half resolution on each axis (the 4:2:0
    /// downsample), clamping at the edges for odd dimensions.
    private static func downsampleChroma(_ plane: [Double], width: Int, height: Int) -> (plane: [Double], width: Int, height: Int) {
        let halfWidth = (width + 1) / 2
        let halfHeight = (height + 1) / 2
        var out = [Double](repeating: 0, count: halfWidth * halfHeight)
        for y in 0 ..< halfHeight {
            let y0 = 2 * y
            let y1 = min(y0 + 1, height - 1)
            for x in 0 ..< halfWidth {
                let x0 = 2 * x
                let x1 = min(x0 + 1, width - 1)
                out[y * halfWidth + x] = (plane[y0 * width + x0] + plane[y0 * width + x1]
                    + plane[y1 * width + x0] + plane[y1 * width + x1]) / 4
            }
        }
        return (out, halfWidth, halfHeight)
    }

    private static func appendDHT(_ out: inout [UInt8], spec: HuffmanSpec, tableClass: Int, id: Int) {
        let length = 2 + 1 + 16 + spec.values.count
        out += [0xFF, 0xC4, UInt8(length >> 8), UInt8(length & 0xFF)]
        out.append(UInt8((tableClass << 4) | id))
        for length in 1 ... 16 {
            out.append(UInt8(spec.bits[length]))
        }
        out += spec.values.map { UInt8($0) }
    }

    private static func appendSOSHeader(_ out: inout [UInt8]) {
        out += [0xFF, 0xDA, 0x00, 0x0C, 0x03] // length 12, three components
        out += [0x01, 0x00] // Y  uses DC/AC table 0
        out += [0x02, 0x11] // Cb uses DC/AC table 1
        out += [0x03, 0x11] // Cr uses DC/AC table 1
        out += [0x00, 0x3F, 0x00] // Ss 0, Se 63, Ah/Al 0
    }

    // MARK: - Bit writer

    /// Accumulates entropy bits MSB-first, stuffing `0x00` after every `0xFF` and padding the
    /// final partial byte with 1-bits, as the JPEG entropy stream requires.
    private struct BitWriter {
        private var bytes: [UInt8] = []
        private var current: UInt32 = 0
        private var count = 0

        mutating func write(_ value: Int, bits: Int) {
            guard bits > 0 else { return }
            var n = bits - 1
            while n >= 0 {
                append(Int((value >> n) & 1))
                n -= 1
            }
        }

        private mutating func append(_ bit: Int) {
            current = (current << 1) | UInt32(bit & 1)
            count += 1
            if count == 8 { flushByte(UInt8(current & 0xFF)) }
        }

        private mutating func flushByte(_ byte: UInt8) {
            bytes.append(byte)
            if byte == 0xFF { bytes.append(0x00) } // byte stuffing
            current = 0
            count = 0
        }

        mutating func finish() -> [UInt8] {
            if count > 0 {
                let padded = UInt8((current << (8 - count)) | ((1 << (8 - count)) - 1))
                flushByte(padded)
            }
            return bytes
        }
    }

    // MARK: - Static data

    /// The zig-zag scan order: `zigZag[k]` is the row-major index of the k-th coefficient.
    private static let zigZag: [Int] = [
        0, 1, 8, 16, 9, 2, 3, 10,
        17, 24, 32, 25, 18, 11, 4, 5,
        12, 19, 26, 33, 40, 48, 41, 34,
        27, 20, 13, 6, 7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36,
        29, 22, 15, 23, 30, 37, 44, 51,
        58, 59, 52, 45, 38, 31, 39, 46,
        53, 60, 61, 54, 47, 55, 62, 63,
    ]

    /// Forward-DCT basis: `fdctBasis[k * 8 + i] = C(k)·cos((2i+1)kπ/16)`, with `C(0) = 1/√2`.
    /// Precomputed so Renderers needs no runtime trig; the same constants the decoder's IDCT uses,
    /// transposed for the forward direction.
    private static let fdctBasis: [Double] = [
        0.70710678118654757, 0.70710678118654757, 0.70710678118654757, 0.70710678118654757, 0.70710678118654757, 0.70710678118654757, 0.70710678118654757, 0.70710678118654757,
        0.98078528040323043, 0.83146961230254524, 0.55557023301960229, 0.19509032201612833, -0.19509032201612819, -0.55557023301960196, -0.83146961230254535, -0.98078528040323043,
        0.92387953251128674, 0.38268343236508984, -0.38268343236508973, -0.92387953251128674, -0.92387953251128685, -0.38268343236509034, 0.38268343236509, 0.92387953251128652,
        0.83146961230254524, -0.19509032201612819, -0.98078528040323043, -0.55557023301960218, 0.55557023301960184, 0.98078528040323043, 0.19509032201612878, -0.83146961230254512,
        0.70710678118654757, -0.70710678118654746, -0.70710678118654768, 0.70710678118654735, 0.70710678118654768, -0.70710678118654668, -0.70710678118654724, 0.70710678118654657,
        0.55557023301960229, -0.98078528040323043, 0.1950903220161283, 0.83146961230254546, -0.83146961230254512, -0.19509032201612803, 0.98078528040323065, -0.55557023301960151,
        0.38268343236508984, -0.92387953251128685, 0.92387953251128652, -0.38268343236508989, -0.38268343236509056, 0.92387953251128674, -0.92387953251128641, 0.38268343236508956,
        0.19509032201612833, -0.55557023301960218, 0.83146961230254546, -0.98078528040323065, 0.98078528040323043, -0.83146961230254501, 0.55557023301960151, -0.19509032201612858,
    ]

    /// Standard luminance quantization table (T.81 Table K.1), natural row-major order.
    private static let baseLuminanceQuant: [Int] = [
        16, 11, 10, 16, 24, 40, 51, 61,
        12, 12, 14, 19, 26, 58, 60, 55,
        14, 13, 16, 24, 40, 57, 69, 56,
        14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68, 109, 103, 77,
        24, 35, 55, 64, 81, 104, 113, 92,
        49, 64, 78, 87, 103, 121, 120, 101,
        72, 92, 95, 98, 112, 100, 103, 99,
    ]

    /// Standard chrominance quantization table (T.81 Table K.2), natural row-major order.
    private static let baseChrominanceQuant: [Int] = [
        17, 18, 24, 47, 99, 99, 99, 99,
        18, 21, 26, 66, 99, 99, 99, 99,
        24, 26, 56, 99, 99, 99, 99, 99,
        47, 66, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
    ]
}
