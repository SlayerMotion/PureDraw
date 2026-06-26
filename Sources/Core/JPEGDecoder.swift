//
//  JPEGDecoder.swift
//  PureDraw
//

/// Decodes baseline (and extended) sequential Huffman JPEG/JFIF into a raw-RGBA `Image`,
/// the JPEG counterpart to `PNGDecoder`. It is invoked from `ImageDecoder.decode` when the
/// leading bytes are the JPEG `SOI` marker (`FF D8`).
///
/// Supported: 8-bit baseline (`SOF0`), extended-sequential (`SOF1`), and progressive (`SOF2`)
/// DCT with Huffman coding, 1-component grayscale and 3-component YCbCr/RGB, arbitrary chroma
/// subsampling (4:4:4, 4:2:2, 4:2:0, 4:1:1), restart intervals, and the Adobe (`APP14`) color
/// transform flag. Arithmetic-coded, 12-bit, and 4-component (CMYK/YCCK) streams are reported as
/// `unsupportedFormat` rather than guessed, so a caller knows decoding did not happen.
enum JPEGDecoder {
    /// Upper bound on `width * height` (64 megapixels). A few header bytes can declare dimensions
    /// up to 65535x65535, so this caps the plane and RGBA allocations a crafted file can request.
    private static let maxPixels = 64_000_000

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

    /// The separable 8x8 inverse-DCT basis: `idctBasis[x * 8 + u] = C(u)·cos((2x+1)uπ/16)`,
    /// with `C(0) = 1/√2` and `C(u>0) = 1`. Precomputed so Core needs no runtime trig (it has
    /// no Foundation). The same matrix drives both the horizontal and vertical passes.
    private static let idctBasis: [Double] = [
        0.70710678118654757, 0.98078528040323043, 0.92387953251128674, 0.83146961230254524, 0.70710678118654757, 0.55557023301960229, 0.38268343236508984, 0.19509032201612833,
        0.70710678118654757, 0.83146961230254524, 0.38268343236508984, -0.19509032201612819, -0.70710678118654746, -0.98078528040323043, -0.92387953251128685, -0.55557023301960218,
        0.70710678118654757, 0.55557023301960229, -0.38268343236508973, -0.98078528040323043, -0.70710678118654768, 0.1950903220161283, 0.92387953251128652, 0.83146961230254546,
        0.70710678118654757, 0.19509032201612833, -0.92387953251128674, -0.55557023301960218, 0.70710678118654735, 0.83146961230254546, -0.38268343236508989, -0.98078528040323065,
        0.70710678118654757, -0.19509032201612819, -0.92387953251128685, 0.55557023301960184, 0.70710678118654768, -0.83146961230254512, -0.38268343236509056, 0.98078528040323043,
        0.70710678118654757, -0.55557023301960196, -0.38268343236509034, 0.98078528040323043, -0.70710678118654668, -0.19509032201612803, 0.92387953251128674, -0.83146961230254501,
        0.70710678118654757, -0.83146961230254535, 0.38268343236509, 0.19509032201612878, -0.70710678118654724, 0.98078528040323065, -0.92387953251128641, 0.55557023301960151,
        0.70710678118654757, -0.98078528040323043, 0.92387953251128652, -0.83146961230254512, 0.70710678118654657, -0.55557023301960151, 0.38268343236508956, -0.19509032201612858,
    ]

    // MARK: - Frame model

    /// One image component declared in the frame header (`SOF`).
    private struct Component {
        var id: Int
        var h: Int // horizontal sampling factor
        var v: Int // vertical sampling factor
        var quantTable: Int // index into the quantization tables
        var dcTable = 0 // DC Huffman table, set by the scan header
        var acTable = 0 // AC Huffman table, set by the scan header
    }

    /// A canonical Huffman table built from a `DHT` segment, decoded with the
    /// min-code/max-code/value-pointer procedure (ITU-T T.81 Annex F).
    private struct HuffTable {
        let values: [Int]
        var minCode = [Int](repeating: 0, count: 17)
        var maxCode = [Int](repeating: -1, count: 17)
        var valPtr = [Int](repeating: 0, count: 17)

        init(bits: [Int], values: [Int]) {
            self.values = values
            // Code sizes, then canonical codes (T.81 Annex C).
            var sizes: [Int] = []
            for length in 1 ... 16 {
                for _ in 0 ..< bits[length - 1] {
                    sizes.append(length)
                }
            }
            var codes = [Int](repeating: 0, count: sizes.count)
            var code = 0
            var k = 0
            var size = sizes.first ?? 0
            while k < sizes.count {
                while k < sizes.count, sizes[k] == size {
                    codes[k] = code
                    code += 1
                    k += 1
                }
                code <<= 1
                size += 1
            }
            var p = 0
            for length in 1 ... 16 where bits[length - 1] > 0 {
                valPtr[length] = p
                minCode[length] = codes[p]
                p += bits[length - 1]
                maxCode[length] = codes[p - 1]
            }
        }
    }

    // MARK: - Entry point

    static func decode(_ data: [UInt8]) throws -> Image {
        var quant = [Int: [Int]]()
        var dcTables = [Int: HuffTable]()
        var acTables = [Int: HuffTable]()
        var components: [Component] = []
        var width = 0
        var height = 0
        var restartInterval = 0
        var adobeTransform: Int? = nil
        var entropyStart = -1
        var progressive = false
        // Progressive coefficients accumulate across scans: one block-major, zig-zag-ordered
        // buffer per component, sized to the padded MCU grid. Empty until the first progressive
        // scan allocates it.
        var coefficients: [[Int]] = []

        var pos = 2 // past SOI (FF D8)
        markers: while pos + 1 < data.count {
            guard data[pos] == 0xFF else { pos += 1
                continue
            }
            // Skip any fill bytes (0xFF) preceding the marker code.
            var mp = pos + 1
            while mp < data.count, data[mp] == 0xFF {
                mp += 1
            }
            guard mp < data.count else { break }
            let marker = data[mp]
            pos = mp + 1

            // EOI ends the stream; TEM and stray restart markers carry no length.
            if marker == 0xD9 { break markers }
            if marker == 0x01 || (0xD0 ... 0xD7).contains(marker) { continue }

            // Every remaining marker introduces a variable-length segment. Validate its extent
            // once, up front, so no individual case can read past the buffer on truncated or
            // crafted input. A malformed JPEG must throw, never trap.
            guard pos + 2 <= data.count else { throw malformed("truncated segment length") }
            let length = beUInt16(data, pos)
            guard length >= 2, pos + length <= data.count else {
                throw malformed("segment 0x\(hex(marker)) overruns the file")
            }
            let segmentEnd = pos + length

            switch marker {
            case 0xC0, 0xC1, 0xC2: // SOF0 baseline / SOF1 extended sequential / SOF2 progressive
                progressive = marker == 0xC2
                guard length >= 8 else { throw malformed("truncated SOF") }
                let precision = Int(data[pos + 2])
                guard precision == 8 else { throw unsupported("\(precision)-bit JPEG") }
                height = beUInt16(data, pos + 3)
                width = beUInt16(data, pos + 5)
                let count = Int(data[pos + 7])
                guard length >= 8 + count * 3 else { throw malformed("truncated SOF component list") }
                components = try (0 ..< count).map { i in
                    let base = pos + 8 + i * 3
                    let sampling = Int(data[base + 1])
                    let component = Component(
                        id: Int(data[base]),
                        h: sampling >> 4,
                        v: sampling & 0x0F,
                        quantTable: Int(data[base + 2])
                    )
                    // A zero sampling factor would make the MCU divisor zero; the spec caps it at 4.
                    guard (1 ... 4).contains(component.h), (1 ... 4).contains(component.v) else {
                        throw malformed("invalid sampling factor \(component.h)x\(component.v)")
                    }
                    return component
                }
            case 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF: // arithmetic / differential / lossless
                throw unsupported("JPEG frame type 0x\(hex(marker))")
            case 0xC4: // DHT
                var p = pos + 2
                while p < segmentEnd {
                    let tableClass = Int(data[p]) >> 4
                    let tableID = Int(data[p]) & 0x0F
                    p += 1
                    guard p + 16 <= segmentEnd else { throw malformed("truncated DHT counts") }
                    var bits = [Int](repeating: 0, count: 16)
                    var total = 0
                    for i in 0 ..< 16 {
                        bits[i] = Int(data[p + i])
                        total += bits[i]
                    }
                    p += 16
                    guard p + total <= segmentEnd else { throw malformed("truncated DHT values") }
                    let values = (0 ..< total).map { Int(data[p + $0]) }
                    p += total
                    let table = HuffTable(bits: bits, values: values)
                    if tableClass == 0 { dcTables[tableID] = table } else { acTables[tableID] = table }
                }
            case 0xDB: // DQT
                var p = pos + 2
                while p < segmentEnd {
                    let precision = Int(data[p]) >> 4
                    let tableID = Int(data[p]) & 0x0F
                    p += 1
                    // Precision is 0 (8-bit) or 1 (16-bit); anything else is malformed, not 16-bit.
                    guard precision == 0 || precision == 1 else { throw malformed("invalid DQT precision \(precision)") }
                    var table = [Int](repeating: 0, count: 64)
                    for k in 0 ..< 64 {
                        if precision == 0 {
                            guard p < segmentEnd else { throw malformed("truncated DQT table") }
                            table[k] = Int(data[p])
                            p += 1
                        } else {
                            guard p + 1 < segmentEnd else { throw malformed("truncated DQT table") }
                            table[k] = beUInt16(data, p)
                            p += 2
                        }
                    }
                    quant[tableID] = table
                }
            case 0xDD: // DRI
                guard length >= 4 else { throw malformed("truncated DRI") }
                restartInterval = beUInt16(data, pos + 2)
            case 0xEE: // APP14 (Adobe)
                if length >= 14, isAdobe(data, pos + 2) { adobeTransform = Int(data[pos + 2 + 11]) }
            case 0xDA: // SOS
                guard length >= 3 else { throw malformed("truncated SOS header") } // scanCount byte must exist
                let scanCount = Int(data[pos + 2])
                guard length >= 6 + scanCount * 2 else { throw malformed("truncated SOS header") }
                var scanComponents: [Int] = []
                for i in 0 ..< scanCount {
                    let base = pos + 3 + i * 2
                    let selector = Int(data[base])
                    let tables = Int(data[base + 1])
                    guard let index = components.firstIndex(where: { $0.id == selector }) else {
                        throw malformed("scan references unknown component \(selector)")
                    }
                    components[index].dcTable = tables >> 4
                    components[index].acTable = tables & 0x0F
                    scanComponents.append(index)
                }
                if !progressive {
                    entropyStart = segmentEnd
                    break markers
                }
                // Progressive: this is one of several scans. Decode it into the coefficient store,
                // then resume the marker loop at the scan's end (the next non-restart marker).
                let spectral = pos + 3 + scanCount * 2
                let ss = Int(data[spectral])
                let se = Int(data[spectral + 1])
                let ah = Int(data[spectral + 2]) >> 4
                let al = Int(data[spectral + 2]) & 0x0F
                guard ss <= se, se < 64, al < 16 else { throw malformed("invalid spectral selection") }
                guard ss != 0 || se == 0 else { throw malformed("DC band must have Se == 0") }
                if coefficients.isEmpty {
                    // Validate dimensions and component count BEFORE allocating the (potentially
                    // large) coefficient store; the post-loop guards run too late for this path.
                    guard width > 0, height > 0, width * height <= maxPixels else {
                        throw unsupported("image dimensions too large (\(width)x\(height))")
                    }
                    guard components.count == 1 || components.count == 3 else {
                        throw unsupported("\(components.count)-component JPEG")
                    }
                    coefficients = allocateCoefficientStore(components: components, width: width, height: height)
                }
                try decodeProgressiveScan(
                    data,
                    from: segmentEnd,
                    scanComponents: scanComponents,
                    components: components,
                    width: width,
                    height: height,
                    dcTables: dcTables,
                    acTables: acTables,
                    ss: ss, se: se, ah: ah, al: al,
                    restartInterval: restartInterval,
                    coefficients: &coefficients
                )
                pos = findNextMarker(data, from: segmentEnd)
                continue
            default: // APPn, COM, and any other length-bearing segment: skip.
                break
            }
            pos = segmentEnd
        }

        guard width > 0, height > 0 else { throw malformed("missing or empty frame header") }
        // Bound the work a few header bytes can request: reject dimensions whose plane and RGBA
        // allocations would be excessive, rather than attempting a multi-gigabyte allocation.
        guard width * height <= maxPixels else {
            throw unsupported("image dimensions too large (\(width)x\(height))")
        }
        guard !components.isEmpty else { throw malformed("no frame header") }
        guard components.count == 1 || components.count == 3 else {
            throw unsupported("\(components.count)-component JPEG")
        }

        let planes: [Plane]
        if progressive {
            guard !coefficients.isEmpty else { throw malformed("no scan data") }
            planes = try finalizeCoefficients(
                coefficients: coefficients,
                components: components,
                quant: quant,
                width: width,
                height: height
            )
        } else {
            guard entropyStart >= 0 else { throw malformed("no scan data") }
            planes = try decodeScan(
                data,
                from: entropyStart,
                width: width,
                height: height,
                components: components,
                quant: quant,
                dcTables: dcTables,
                acTables: acTables,
                restartInterval: restartInterval
            )
        }
        let rgba = assembleRGBA(
            planes: planes,
            components: components,
            width: width,
            height: height,
            adobeTransform: adobeTransform
        )
        do {
            return try Image(width: width, height: height, alphaInfo: .last, data: rgba)
        } catch {
            throw malformed("decoded pixel buffer does not match the declared size")
        }
    }

    // MARK: - Entropy-coded scan

    /// A fully decoded component plane of 8-bit spatial samples, padded out to whole MCUs.
    private struct Plane {
        var samples: [UInt8]
        var width: Int // padded width in samples
        var h: Int // sampling factor, for upsampling
        var v: Int
    }

    private static func decodeScan(
        _ data: [UInt8],
        from start: Int,
        width: Int,
        height: Int,
        components: [Component],
        quant: [Int: [Int]],
        dcTables: [Int: HuffTable],
        acTables: [Int: HuffTable],
        restartInterval: Int
    ) throws -> [Plane] {
        let hMax = components.map(\.h).max() ?? 1
        let vMax = components.map(\.v).max() ?? 1
        let mcusPerLine = (width + 8 * hMax - 1) / (8 * hMax)
        let mcusPerColumn = (height + 8 * vMax - 1) / (8 * vMax)

        var planes = components.map { component in
            Plane(
                samples: [UInt8](repeating: 0, count: mcusPerLine * component.h * 8 * mcusPerColumn * component.v * 8),
                width: mcusPerLine * component.h * 8,
                h: component.h,
                v: component.v
            )
        }

        // Resolve each component's quant and Huffman tables once: they are fixed for the whole
        // scan, so the per-MCU dictionary lookups belong outside the hot loop.
        let resolved: [(component: Component, quant: [Int], dc: HuffTable, ac: HuffTable)] = try components.map {
            guard let quant = quant[$0.quantTable], let dc = dcTables[$0.dcTable], let ac = acTables[$0.acTable] else {
                throw malformed("scan references a missing table")
            }
            return ($0, quant, dc, ac)
        }

        var reader = BitReader(data: data, position: start)
        var predictors = [Int](repeating: 0, count: resolved.count)
        var block = [Double](repeating: 0, count: 64)
        var spatial = [Double](repeating: 0, count: 64)
        var scratch = [Double](repeating: 0, count: 64) // reused IDCT intermediate, written before read
        var mcusDecoded = 0

        for mcuY in 0 ..< mcusPerColumn {
            for mcuX in 0 ..< mcusPerLine {
                if restartInterval > 0, mcusDecoded > 0, mcusDecoded % restartInterval == 0 {
                    reader.restart()
                    for i in predictors.indices {
                        predictors[i] = 0
                    }
                }
                for (index, entry) in resolved.enumerated() {
                    let component = entry.component
                    for by in 0 ..< component.v {
                        for bx in 0 ..< component.h {
                            try decodeBlock(
                                &reader,
                                dc: entry.dc,
                                ac: entry.ac,
                                quant: entry.quant,
                                predictor: &predictors[index],
                                coefficients: &block
                            )
                            inverseDCT(block, into: &spatial, scratch: &scratch)
                            let originX = (mcuX * component.h + bx) * 8
                            let originY = (mcuY * component.v + by) * 8
                            place(spatial, into: &planes[index], originX: originX, originY: originY)
                        }
                    }
                }
                mcusDecoded += 1
            }
        }
        return planes
    }

    /// Decodes one 8x8 block into dequantized, de-zig-zagged coefficients (`coefficients`).
    private static func decodeBlock(
        _ reader: inout BitReader,
        dc: HuffTable,
        ac: HuffTable,
        quant: [Int],
        predictor: inout Int,
        coefficients: inout [Double]
    ) throws {
        for i in 0 ..< 64 {
            coefficients[i] = 0
        }

        let dcCategory = try decodeHuffman(&reader, dc)
        // A corrupt DHT can map a code to an out-of-range symbol; cap the bit count so the shifts
        // in receive()/extend() cannot overflow Int. (AC `size` is a 4-bit nibble, already bounded.)
        guard dcCategory <= 16 else { throw malformed("invalid DC coefficient category \(dcCategory)") }
        let diff = dcCategory == 0 ? 0 : extend(reader.receive(dcCategory), dcCategory)
        predictor += diff
        coefficients[0] = Double(predictor * quant[0])

        var k = 1
        while k < 64 {
            let runSize = try decodeHuffman(&reader, ac)
            let run = runSize >> 4
            let size = runSize & 0x0F
            if size == 0 {
                if run == 15 { k += 16
                    continue
                } // ZRL: 16 zeros
                break // EOB
            }
            k += run
            guard k < 64 else { break }
            let value = extend(reader.receive(size), size)
            coefficients[zigZag[k]] = Double(value * quant[k])
            k += 1
        }
    }

    /// The DECODE procedure (T.81 Annex F): read bits a length at a time until the accumulated
    /// code falls within a length's code range, then look up the symbol.
    private static func decodeHuffman(_ reader: inout BitReader, _ table: HuffTable) throws -> Int {
        var code = 0
        for length in 1 ... 16 {
            code = (code << 1) | reader.bit()
            if table.maxCode[length] >= 0, code <= table.maxCode[length] {
                return table.values[table.valPtr[length] + code - table.minCode[length]]
            }
        }
        throw malformed("invalid Huffman code")
    }

    /// Sign-extends an `s`-bit magnitude into a signed coefficient (T.81 Annex F.2.2.1).
    private static func extend(_ value: Int, _ size: Int) -> Int {
        value < (1 << (size - 1)) ? value + (-1 << size) + 1 : value
    }

    // MARK: - Inverse DCT

    /// Separable inverse DCT of `block` (row-major coefficients) into `output` spatial samples,
    /// level-shifted by +128 but not yet clamped (the caller rounds and clamps). `scratch` is a
    /// caller-owned 64-element buffer reused across blocks; every entry is written before it is
    /// read, so it needs no zeroing.
    private static func inverseDCT(_ block: [Double], into output: inout [Double], scratch intermediate: inout [Double]) {
        // Bind the static basis to a local so the inner loops use a plain array, not the lazy
        // global accessor.
        let basis = idctBasis

        // DC-only fast path: when no AC coefficient is present (common in smooth regions, and the
        // case the grayscale tests exercise) the block is flat. Compute the flat value exactly the
        // way the full transform would, so results are identical to the general path.
        var hasAC = false
        for i in 1 ..< 64 where block[i] != 0 {
            hasAC = true
            break
        }
        if !hasAC {
            // Reproduce the full transform's exact operand association for a DC-only block so the
            // result is bit-identical (the two passes each reduce to a single column-0 term):
            //   horizontal -> intermediate = basis[0] * block[0]
            //   vertical   -> output       = basis[0] * intermediate * 0.25 + 128
            // Grouping matters: basis[0]*basis[0] rounds to 0.5000000000000001, not 0.5, so the
            // multiplications must nest the same way the loops accumulate them.
            let dc = basis[0] // C(0)·cos(0)
            let intermediate = dc * block[0]
            let flat = dc * intermediate * 0.25 + 128.0
            for i in 0 ..< 64 {
                output[i] = flat
            }
            return
        }

        // Horizontal pass: for each row of coefficients, 1-D IDCT across the u (column) axis.
        for row in 0 ..< 8 {
            let base = row * 8
            for x in 0 ..< 8 {
                var sum = 0.0
                for u in 0 ..< 8 {
                    sum += basis[x * 8 + u] * block[base + u]
                }
                intermediate[base + x] = sum
            }
        }
        // Vertical pass: for each column, 1-D IDCT across the v (row) axis; scale by 1/4.
        for x in 0 ..< 8 {
            for y in 0 ..< 8 {
                var sum = 0.0
                for v in 0 ..< 8 {
                    sum += basis[y * 8 + v] * intermediate[v * 8 + x]
                }
                output[y * 8 + x] = sum * 0.25 + 128.0
            }
        }
    }

    private static func place(_ spatial: [Double], into plane: inout Plane, originX: Int, originY: Int) {
        for y in 0 ..< 8 {
            let dstRow = (originY + y) * plane.width + originX
            let srcRow = y * 8
            for x in 0 ..< 8 {
                plane.samples[dstRow + x] = clampByte(spatial[srcRow + x])
            }
        }
    }

    // MARK: - Progressive

    /// The interleaved-MCU grid for a frame: the max sampling factors and the MCU counts.
    private static func mcuGrid(_ components: [Component], width: Int, height: Int) -> (hMax: Int, vMax: Int, perLine: Int, perColumn: Int) {
        let hMax = components.map(\.h).max() ?? 1
        let vMax = components.map(\.v).max() ?? 1
        return (hMax, vMax, (width + 8 * hMax - 1) / (8 * hMax), (height + 8 * vMax - 1) / (8 * vMax))
    }

    /// One zig-zag-ordered coefficient buffer per component, sized to the padded MCU block grid.
    ///
    /// Progressive decoding must buffer every coefficient across scans (unlike baseline, which
    /// transforms each block immediately), so this is inherently large: ~`width * height` entries
    /// per component, bounded by the `maxPixels` cap. `Int` is used rather than a 16-bit coefficient
    /// type so the accumulate/refine arithmetic cannot overflow and trap on malformed input, keeping
    /// the throw-don't-trap contract; the trade is a larger but still capped allocation.
    private static func allocateCoefficientStore(components: [Component], width: Int, height: Int) -> [[Int]] {
        let grid = mcuGrid(components, width: width, height: height)
        return components.map { [Int](repeating: 0, count: grid.perLine * $0.h * grid.perColumn * $0.v * 64) }
    }

    /// The byte offset of the next real marker at or after `start`, skipping `FF 00` stuffing and
    /// restart markers (both part of the entropy stream). Used to resume the marker loop after a
    /// progressive scan.
    private static func findNextMarker(_ data: [UInt8], from start: Int) -> Int {
        var p = start
        while p + 1 < data.count {
            if data[p] == 0xFF {
                let next = data[p + 1]
                if next != 0x00, !(0xD0 ... 0xD7).contains(next) { return p }
            }
            p += 1
        }
        return data.count
    }

    /// Decodes one progressive scan into the coefficient store. A DC scan (`ss == 0`) is interleaved
    /// across the scan's components; an AC scan addresses a single component's blocks in raster
    /// order. `ah == 0` is a first scan (initial bits, point-transformed by `al`); `ah > 0` a
    /// refinement that appends one more bit.
    private static func decodeProgressiveScan(
        _ data: [UInt8],
        from start: Int,
        scanComponents: [Int],
        components: [Component],
        width: Int,
        height: Int,
        dcTables: [Int: HuffTable],
        acTables: [Int: HuffTable],
        ss: Int, se: Int, ah: Int, al: Int,
        restartInterval: Int,
        coefficients: inout [[Int]]
    ) throws {
        guard !scanComponents.isEmpty else { throw malformed("scan declares no components") }
        let grid = mcuGrid(components, width: width, height: height)
        var reader = BitReader(data: data, position: start)
        var eobrun = 0

        // Interleaving is decided by the component count, not the band: a multi-component scan is
        // interleaved (and per the spec must be a DC scan); a single-component scan is
        // non-interleaved, whether it is the DC band or an AC band.
        if scanComponents.count > 1 {
            guard ss == 0 else { throw malformed("interleaved progressive scan must be a DC scan") }
            var predictors = [Int](repeating: 0, count: components.count)
            var decoded = 0
            for mcuY in 0 ..< grid.perColumn {
                for mcuX in 0 ..< grid.perLine {
                    if restartInterval > 0, decoded > 0, decoded % restartInterval == 0 {
                        reader.restart()
                        for i in predictors.indices {
                            predictors[i] = 0
                        }
                    }
                    for ci in scanComponents {
                        let component = components[ci]
                        guard let dc = dcTables[component.dcTable] else { throw malformed("scan references a missing table") }
                        let blocksWide = grid.perLine * component.h
                        for by in 0 ..< component.v {
                            for bx in 0 ..< component.h {
                                let offset = ((mcuY * component.v + by) * blocksWide + (mcuX * component.h + bx)) * 64
                                try decodeProgressiveDC(&reader, &coefficients[ci], offset: offset, ah: ah, al: al, dc: dc, predictor: &predictors[ci])
                            }
                        }
                    }
                    decoded += 1
                }
            }
        } else {
            // Single component, non-interleaved: iterate the component's own block grid.
            let ci = scanComponents[0]
            let component = components[ci]
            let blocksWide = grid.perLine * component.h
            let samplesWide = (width * component.h + grid.hMax - 1) / grid.hMax
            let samplesHigh = (height * component.v + grid.vMax - 1) / grid.vMax
            let blocksPerLine = (samplesWide + 7) / 8
            let blocksPerColumn = (samplesHigh + 7) / 8
            var predictor = 0
            var decoded = 0

            if ss == 0 {
                guard let dc = dcTables[component.dcTable] else { throw malformed("scan references a missing table") }
                for blockRow in 0 ..< blocksPerColumn {
                    for blockCol in 0 ..< blocksPerLine {
                        if restartInterval > 0, decoded > 0, decoded % restartInterval == 0 {
                            reader.restart()
                            predictor = 0
                        }
                        let offset = (blockRow * blocksWide + blockCol) * 64
                        try decodeProgressiveDC(&reader, &coefficients[ci], offset: offset, ah: ah, al: al, dc: dc, predictor: &predictor)
                        decoded += 1
                    }
                }
            } else {
                guard let ac = acTables[component.acTable] else { throw malformed("scan references a missing table") }
                for blockRow in 0 ..< blocksPerColumn {
                    for blockCol in 0 ..< blocksPerLine {
                        if restartInterval > 0, decoded > 0, decoded % restartInterval == 0 {
                            reader.restart()
                            eobrun = 0
                        }
                        let offset = (blockRow * blocksWide + blockCol) * 64
                        if ah == 0 {
                            try decodeACFirst(&reader, &coefficients[ci], offset: offset, ss: ss, se: se, al: al, ac: ac, eobrun: &eobrun)
                        } else {
                            try decodeACRefine(&reader, &coefficients[ci], offset: offset, ss: ss, se: se, al: al, ac: ac, eobrun: &eobrun)
                        }
                        decoded += 1
                    }
                }
            }
        }
    }

    /// Decodes one block's progressive DC: an `ah == 0` first scan accumulates the predicted DC
    /// (point-transformed by `al`); an `ah > 0` refinement appends one lower bit.
    private static func decodeProgressiveDC(
        _ reader: inout BitReader,
        _ coef: inout [Int],
        offset: Int,
        ah: Int, al: Int,
        dc: HuffTable,
        predictor: inout Int
    ) throws {
        if ah == 0 {
            let category = try decodeHuffman(&reader, dc)
            guard category <= 16 else { throw malformed("invalid DC category \(category)") }
            let diff = category == 0 ? 0 : extend(reader.receive(category), category)
            predictor += diff
            coef[offset] = predictor << al
        } else if reader.bit() != 0 {
            coef[offset] |= (1 << al)
        }
    }

    /// First AC scan of a band (`ah == 0`): place new coefficients shifted by `al`, with
    /// end-of-band run handling (ITU-T T.81 G.1.2.2).
    private static func decodeACFirst(
        _ reader: inout BitReader,
        _ coef: inout [Int],
        offset: Int,
        ss: Int, se: Int, al: Int,
        ac: HuffTable,
        eobrun: inout Int
    ) throws {
        if eobrun > 0 { eobrun -= 1
            return
        }
        var k = ss
        while k <= se {
            let rs = try decodeHuffman(&reader, ac)
            let run = rs >> 4
            let size = rs & 0x0F
            if size == 0 {
                if run != 15 {
                    // EOB run: this block plus a counted-down number of following blocks are empty
                    // in this band.
                    eobrun = (1 << run) - 1
                    if run != 0 { eobrun += reader.receive(run) }
                    break
                }
                k += 16 // ZRL: sixteen zero coefficients
            } else {
                k += run
                guard k <= se else { break }
                coef[offset + k] = extend(reader.receive(size), size) << al
                k += 1
            }
        }
    }

    /// Refinement AC scan of a band (`ah > 0`): append one bit to existing coefficients and place
    /// newly nonzero ones, applying correction bits across the band (ITU-T T.81 G.1.2.3).
    private static func decodeACRefine(
        _ reader: inout BitReader,
        _ coef: inout [Int],
        offset: Int,
        ss: Int, se: Int, al: Int,
        ac: HuffTable,
        eobrun: inout Int
    ) throws {
        let positive = 1 << al
        let negative = -1 << al
        var k = ss

        if eobrun == 0 {
            while k <= se {
                let rs = try decodeHuffman(&reader, ac)
                var run = rs >> 4
                let size = rs & 0x0F
                var newValue = 0
                if size == 0 {
                    if run != 15 {
                        eobrun = 1 << run
                        if run != 0 { eobrun += reader.receive(run) }
                        break
                    }
                    // run == 15: skip sixteen zero-history coefficients (nonzero ones don't count).
                } else {
                    // In a refinement scan the only legal magnitude is 1; anything else is malformed.
                    guard size == 1 else { throw malformed("AC refinement coefficient size must be 1") }
                    newValue = reader.bit() != 0 ? positive : negative
                }
                // Advance over `run` zero-history coefficients, correcting nonzero ones en route.
                // The correction bit must be read from the live reader for every nonzero coefficient.
                while k <= se {
                    let index = offset + k
                    if coef[index] != 0 {
                        if reader.bit() != 0, (coef[index] & positive) == 0 {
                            coef[index] += coef[index] > 0 ? positive : negative
                        }
                    } else {
                        if run == 0 { break }
                        run -= 1
                    }
                    k += 1
                }
                if newValue != 0, k <= se {
                    coef[offset + k] = newValue
                }
                k += 1
            }
        }

        if eobrun > 0 {
            while k <= se {
                let index = offset + k
                if coef[index] != 0, reader.bit() != 0, (coef[index] & positive) == 0 {
                    coef[index] += coef[index] > 0 ? positive : negative
                }
                k += 1
            }
            eobrun -= 1
        }
    }

    /// Dequantizes, de-zig-zags, and inverse-transforms the accumulated progressive coefficients
    /// into component sample planes, reusing the baseline inverse-DCT and placement.
    private static func finalizeCoefficients(
        coefficients: [[Int]],
        components: [Component],
        quant: [Int: [Int]],
        width: Int,
        height: Int
    ) throws -> [Plane] {
        let grid = mcuGrid(components, width: width, height: height)
        var planes = components.map { component in
            Plane(
                samples: [UInt8](repeating: 0, count: grid.perLine * component.h * 8 * grid.perColumn * component.v * 8),
                width: grid.perLine * component.h * 8,
                h: component.h,
                v: component.v
            )
        }
        var block = [Double](repeating: 0, count: 64)
        var spatial = [Double](repeating: 0, count: 64)
        var scratch = [Double](repeating: 0, count: 64)
        for (ci, component) in components.enumerated() {
            guard let quantTable = quant[component.quantTable] else { throw malformed("missing quantization table") }
            let blocksWide = grid.perLine * component.h
            let blocksHigh = grid.perColumn * component.v
            for blockRow in 0 ..< blocksHigh {
                for blockCol in 0 ..< blocksWide {
                    let offset = (blockRow * blocksWide + blockCol) * 64
                    for i in 0 ..< 64 {
                        block[i] = 0
                    }
                    for k in 0 ..< 64 {
                        block[zigZag[k]] = Double(coefficients[ci][offset + k] * quantTable[k])
                    }
                    inverseDCT(block, into: &spatial, scratch: &scratch)
                    place(spatial, into: &planes[ci], originX: blockCol * 8, originY: blockRow * 8)
                }
            }
        }
        return planes
    }

    // MARK: - Color reconstruction

    private static func assembleRGBA(
        planes: [Plane],
        components: [Component],
        width: Int,
        height: Int,
        adobeTransform: Int?
    ) -> [UInt8] {
        let hMax = components.map(\.h).max() ?? 1
        let vMax = components.map(\.v).max() ?? 1
        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        if planes.count == 1 {
            let plane = planes[0]
            for y in 0 ..< height {
                let rowBase = y * plane.width
                var dst = y * width * 4
                for x in 0 ..< width {
                    let g = plane.samples[rowBase + x]
                    rgba[dst] = g
                    rgba[dst + 1] = g
                    rgba[dst + 2] = g
                    rgba[dst + 3] = 255
                    dst += 4
                }
            }
            return rgba
        }

        // Three components. APP14 transform 0 means the samples are already R,G,B; otherwise
        // (or absent, the JFIF default) they are YCbCr. YCCK/CMYK (transform 2 / 4 components)
        // is rejected earlier. The chroma row offset depends only on y, so it is hoisted out of
        // the inner loop, which then nearest-samples each plane with a single division per pixel.
        let p0 = planes[0], p1 = planes[1], p2 = planes[2]
        let isRGB = adobeTransform == 0
        // The horizontal sample index repeats identically across every row, so build each plane's
        // column-mapping table once instead of dividing per pixel.
        let cols0 = (0 ..< width).map { $0 * p0.h / hMax }
        let cols1 = (0 ..< width).map { $0 * p1.h / hMax }
        let cols2 = (0 ..< width).map { $0 * p2.h / hMax }
        for y in 0 ..< height {
            let r0 = (y * p0.v / vMax) * p0.width
            let r1 = (y * p1.v / vMax) * p1.width
            let r2 = (y * p2.v / vMax) * p2.width
            var dst = y * width * 4
            for x in 0 ..< width {
                let c0 = p0.samples[r0 + cols0[x]]
                let c1 = p1.samples[r1 + cols1[x]]
                let c2 = p2.samples[r2 + cols2[x]]
                if isRGB {
                    rgba[dst] = c0
                    rgba[dst + 1] = c1
                    rgba[dst + 2] = c2
                } else {
                    let yy = Double(c0)
                    let cb = Double(c1) - 128.0
                    let cr = Double(c2) - 128.0
                    rgba[dst] = clampByte(yy + 1.402 * cr)
                    rgba[dst + 1] = clampByte(yy - 0.344136 * cb - 0.714136 * cr)
                    rgba[dst + 2] = clampByte(yy + 1.772 * cb)
                }
                rgba[dst + 3] = 255
                dst += 4
            }
        }
        return rgba
    }

    // MARK: - Bit reader

    /// Reads entropy-coded bits MSB-first, unstuffing `FF 00` and stopping at any other marker.
    private struct BitReader {
        let data: [UInt8]
        var position: Int
        private var buffer: UInt32 = 0
        private var count: Int = 0
        /// The marker byte the reader ran into (0 while still inside entropy data).
        private(set) var marker = 0

        init(data: [UInt8], position: Int) {
            self.data = data
            self.position = position
        }

        mutating func bit() -> Int {
            if count == 0 { fill() }
            count -= 1
            return Int((buffer >> count) & 1)
        }

        /// Reads `size` bits as an unsigned integer (MSB first).
        mutating func receive(_ size: Int) -> Int {
            var value = 0
            for _ in 0 ..< size {
                value = (value << 1) | bit()
            }
            return value
        }

        private mutating func fill() {
            // Once a marker is reached, feed zero bits (the padding the standard mandates).
            if marker != 0 { buffer = 0
                count = 8
                return
            }
            guard position < data.count else { buffer = 0
                count = 8
                return
            }
            var byte = data[position]
            position += 1
            if byte == 0xFF {
                var next = position < data.count ? data[position] : 0xD9
                position += 1
                while next == 0xFF {
                    next = position < data.count ? data[position] : 0xD9
                    position += 1
                }
                if next == 0x00 {
                    byte = 0xFF // stuffed literal
                } else {
                    marker = Int(next)
                    buffer = 0
                    count = 8
                    return
                }
            }
            buffer = UInt32(byte)
            count = 8
        }

        /// Aligns to the next restart marker and resumes after it.
        mutating func restart() {
            buffer = 0
            count = 0
            // Always clear `marker`, even when fill() stopped on a non-restart marker; otherwise
            // fill() would keep feeding zero bits and blank the remainder of the scan.
            let consumedRestart = (0xD0 ... 0xD7).contains(marker)
            marker = 0
            if consumedRestart { return } // fill() already advanced past the RSTn
            while position + 1 < data.count {
                if data[position] == 0xFF, data[position + 1] >= 0xD0, data[position + 1] <= 0xD7 {
                    position += 2
                    return
                }
                position += 1
            }
        }
    }

    // MARK: - Helpers

    private static func clampByte(_ value: Double) -> UInt8 {
        if value <= 0 { return 0 }
        if value >= 255 { return 255 }
        return UInt8(value.rounded())
    }

    private static func beUInt16(_ data: [UInt8], _ offset: Int) -> Int {
        Int(data[offset]) << 8 | Int(data[offset + 1])
    }

    private static func isAdobe(_ data: [UInt8], _ offset: Int) -> Bool {
        let tag: [UInt8] = [0x41, 0x64, 0x6F, 0x62, 0x65] // "Adobe"
        guard offset + tag.count <= data.count else { return false }
        return Array(data[offset ..< offset + tag.count]) == tag
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
