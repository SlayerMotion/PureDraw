//
//  Deflate.swift
//  PureDraw
//

/// A DEFLATE compressor (RFC 1951), the encoding counterpart to ``Inflate``. It matches with LZ77
/// (a hash-chain sliding-window finder) and codes each block with the cheapest of dynamic Huffman
/// (per-block optimal trees), fixed Huffman, or a stored block. Pure Swift, no Foundation; used for
/// PNG `IDAT` and PDF `FlateDecode` streams. ``Inflate`` and the system zlib both decode its output.
///
/// Greedy (non-lazy) matching is the one deliberate scope limit: lazy evaluation would tighten the
/// ratio a little further. Everything else (dynamic trees, length-limited code lengths, per-block
/// type selection) is the full algorithm.
public enum Deflate {
    /// Compresses `input` into a raw DEFLATE stream. Never larger than a stored encoding (the
    /// per-block selection always includes the stored alternative).
    public static func compressed(_ input: [UInt8]) -> [UInt8] {
        var writer = BitWriter()
        let count = input.count
        if count == 0 {
            writeStoredBlock(input, from: 0, to: 0, isFinal: true, into: &writer)
            return writer.finish()
        }

        // Hash-chain match finder over a 32 KB window.
        var head = [Int](repeating: -1, count: 1 << hashBits)
        var chain = [Int](repeating: -1, count: count)
        func hash(_ i: Int) -> Int {
            (Int(input[i]) << 10 ^ Int(input[i + 1]) << 5 ^ Int(input[i + 2])) & ((1 << hashBits) - 1)
        }
        func insert(_ i: Int) {
            guard i + 2 < count else { return }
            let h = hash(i)
            chain[i] = head[h]
            head[h] = i
        }

        var tokens: [Token] = []
        tokens.reserveCapacity(min(count, blockTokenLimit) + 1)
        var litFreq = [Int](repeating: 0, count: literalCount)
        var distFreq = [Int](repeating: 0, count: distanceCount)
        var blockStart = 0

        func flush(end: Int, isFinal: Bool) {
            writeBlock(input, from: blockStart, to: end, tokens: tokens, litFreq: litFreq, distFreq: distFreq, isFinal: isFinal, into: &writer)
            tokens.removeAll(keepingCapacity: true)
            for i in 0 ..< litFreq.count {
                litFreq[i] = 0
            }
            for i in 0 ..< distFreq.count {
                distFreq[i] = 0
            }
            blockStart = end
        }

        var i = 0
        while i < count {
            var matchLength = 0
            var matchDistance = 0
            if i + minMatch - 1 < count {
                let maxLength = min(maxMatch, count - i)
                var candidate = head[hash(i)]
                var attempts = 0
                while candidate >= 0, i - candidate <= windowSize, attempts < maxChain {
                    if input[candidate + matchLength] == input[i + matchLength] {
                        var length = 0
                        while length < maxLength, input[candidate + length] == input[i + length] {
                            length += 1
                        }
                        if length > matchLength {
                            matchLength = length
                            matchDistance = i - candidate
                            if length >= maxLength { break }
                        }
                    }
                    candidate = chain[candidate]
                    attempts += 1
                }
            }

            if matchLength >= minMatch {
                let lengthCode = lengthCodeFor[matchLength]
                let distanceCode = distanceCodeFor(matchDistance)
                tokens.append(Token(literal: -1, length: matchLength, distance: matchDistance))
                litFreq[257 + lengthCode] += 1
                distFreq[distanceCode] += 1
                let end = i + matchLength
                while i < end {
                    insert(i)
                    i += 1
                }
            } else {
                tokens.append(Token(literal: Int(input[i]), length: 0, distance: 0))
                litFreq[Int(input[i])] += 1
                insert(i)
                i += 1
            }

            if tokens.count >= blockTokenLimit, i < count { flush(end: i, isFinal: false) }
        }
        flush(end: count, isFinal: true)
        return writer.finish()
    }

    private struct Token {
        var literal: Int // >= 0 for a literal byte; -1 for a length/distance match
        var length: Int
        var distance: Int
    }

    // MARK: - Block emission

    /// Writes one block as whichever of dynamic Huffman, fixed Huffman, or stored is smallest.
    private static func writeBlock(
        _ input: [UInt8],
        from start: Int,
        to end: Int,
        tokens: [Token],
        litFreq: [Int],
        distFreq: [Int],
        isFinal: Bool,
        into writer: inout BitWriter
    ) {
        var litFreq = litFreq
        litFreq[endOfBlock] += 1 // every block ends with the end-of-block symbol

        let fixedCost = tokenCost(tokens, litLengths: fixedLiteralLengths, distLengths: fixedDistanceLengths)
        let storedCost = 8 * (5 + (end - start)) + 8 // header + LEN/NLEN + data, plus up to a byte of alignment

        // Dynamic: optimal per-block trees. Skipped when no distances are used (the all-literal case),
        // where an empty distance tree adds a needless edge case and fixed/stored already win.
        var dynamic: DynamicTables? = nil
        if distFreq.contains(where: { $0 > 0 }) {
            dynamic = DynamicTables(litFreq: litFreq, distFreq: distFreq)
        }
        let dynamicCost = dynamic.map { $0.headerBits + tokenCost(tokens, litLengths: $0.litLengths, distLengths: $0.distLengths) } ?? Int.max

        if let dynamic, dynamicCost <= fixedCost, dynamicCost <= storedCost {
            writer.writeBits(isFinal ? 1 : 0, 1)
            writer.writeBits(2, 2) // BTYPE 10 = dynamic Huffman
            dynamic.writeHeader(into: &writer)
            writeTokens(tokens, litCodes: dynamic.litCodes, litLengths: dynamic.litLengths, distCodes: dynamic.distCodes, distLengths: dynamic.distLengths, into: &writer)
        } else if fixedCost <= storedCost {
            writer.writeBits(isFinal ? 1 : 0, 1)
            writer.writeBits(1, 2) // BTYPE 01 = fixed Huffman
            writeTokens(tokens, litCodes: fixedLiteralCodes, litLengths: fixedLiteralLengths, distCodes: fixedDistanceCodes, distLengths: fixedDistanceLengths, into: &writer)
        } else {
            writeStoredBlock(input, from: start, to: end, isFinal: isFinal, into: &writer)
        }
    }

    /// The number of bits the tokens (plus the end-of-block symbol) cost under the given code lengths.
    private static func tokenCost(_ tokens: [Token], litLengths: [Int], distLengths: [Int]) -> Int {
        var bits = litLengths[endOfBlock]
        for token in tokens {
            if token.literal >= 0 {
                bits += litLengths[token.literal]
            } else {
                let lengthCode = lengthCodeFor[token.length]
                bits += litLengths[257 + lengthCode] + lengthExtraBits[lengthCode]
                let distanceCode = distanceCodeFor(token.distance)
                bits += distLengths[distanceCode] + distanceExtraBits[distanceCode]
            }
        }
        return bits
    }

    private static func writeTokens(
        _ tokens: [Token],
        litCodes: [Int],
        litLengths: [Int],
        distCodes: [Int],
        distLengths: [Int],
        into writer: inout BitWriter
    ) {
        for token in tokens {
            if token.literal >= 0 {
                writer.writeBits(litCodes[token.literal], litLengths[token.literal])
            } else {
                let lengthCode = lengthCodeFor[token.length]
                writer.writeBits(litCodes[257 + lengthCode], litLengths[257 + lengthCode])
                writer.writeBits(token.length - lengthBase[lengthCode], lengthExtraBits[lengthCode])
                let distanceCode = distanceCodeFor(token.distance)
                writer.writeBits(distCodes[distanceCode], distLengths[distanceCode])
                writer.writeBits(token.distance - distanceBase[distanceCode], distanceExtraBits[distanceCode])
            }
        }
        writer.writeBits(litCodes[endOfBlock], litLengths[endOfBlock])
    }

    private static func writeStoredBlock(_ input: [UInt8], from start: Int, to end: Int, isFinal: Bool, into writer: inout BitWriter) {
        var offset = start
        repeat {
            let length = min(65535, end - offset)
            let last = isFinal && offset + length == end
            writer.writeBits(last ? 1 : 0, 1)
            writer.writeBits(0, 2) // BTYPE 00 = stored
            writer.alignToByte()
            writer.writeBytes([UInt8(length & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(~length & 0xFF), UInt8((~length >> 8) & 0xFF)])
            if length > 0 { writer.writeBytes(Array(input[offset ..< offset + length])) }
            offset += length
        } while offset < end
    }

    // MARK: - Dynamic Huffman tables

    /// The per-block optimal Huffman trees plus the encoded header that transmits them.
    private struct DynamicTables {
        let litLengths: [Int]
        let distLengths: [Int]
        let litCodes: [Int]
        let distCodes: [Int]
        let headerBits: Int

        private let hlit: Int
        private let hdist: Int
        private let codeLengthCodeLengths: [Int] // by symbol 0...18
        private let codeLengthCodes: [Int]
        private let runLength: [(symbol: Int, extra: Int, extraBits: Int)]

        init(litFreq: [Int], distFreq: [Int]) {
            var litLengths = buildCodeLengths(litFreq, limit: 15)
            var distLengths = buildCodeLengths(distFreq, limit: 15)
            // A block can use literals only; the distance tree still needs one code so the header is
            // well-formed (an incomplete single-code tree, never read because there are no matches).
            if !distLengths.contains(where: { $0 > 0 }) { distLengths[0] = 1 }

            // Transmit at least 257 literal/length and 1 distance code lengths (the format minimums),
            // extended to the highest used symbol.
            var litCount = 257
            for symbol in 257 ..< litLengths.count where litLengths[symbol] > 0 {
                litCount = symbol + 1
            }
            var distCount = 1
            for symbol in 1 ..< distLengths.count where distLengths[symbol] > 0 {
                distCount = symbol + 1
            }

            self.litLengths = litLengths
            self.distLengths = distLengths
            litCodes = encodeTable(litLengths)
            distCodes = encodeTable(distLengths)
            hlit = litCount
            hdist = distCount

            // Run-length encode the concatenated code-length sequence (RFC 1951 §3.2.7).
            let sequence = Array(litLengths[0 ..< litCount]) + Array(distLengths[0 ..< distCount])
            let runs = Self.runLengthEncode(sequence)
            runLength = runs

            var clFreq = [Int](repeating: 0, count: 19)
            for run in runs {
                clFreq[run.symbol] += 1
            }
            let clLengths = buildCodeLengths(clFreq, limit: 7)
            codeLengthCodeLengths = clLengths
            codeLengthCodes = encodeTable(clLengths)

            // Header size, in bits: HLIT/HDIST/HCLEN, the code-length-code lengths, then the runs.
            var hclen = codeLengthOrder.count
            while hclen > 4, clLengths[codeLengthOrder[hclen - 1]] == 0 {
                hclen -= 1
            }
            var bits = 5 + 5 + 4 + hclen * 3
            for run in runs {
                bits += clLengths[run.symbol] + run.extraBits
            }
            headerBits = bits
        }

        func writeHeader(into writer: inout BitWriter) {
            var hclen = codeLengthOrder.count
            while hclen > 4, codeLengthCodeLengths[codeLengthOrder[hclen - 1]] == 0 {
                hclen -= 1
            }
            writer.writeBits(hlit - 257, 5)
            writer.writeBits(hdist - 1, 5)
            writer.writeBits(hclen - 4, 4)
            for index in 0 ..< hclen {
                writer.writeBits(codeLengthCodeLengths[codeLengthOrder[index]], 3)
            }
            for run in runLength {
                writer.writeBits(codeLengthCodes[run.symbol], codeLengthCodeLengths[run.symbol])
                if run.extraBits > 0 { writer.writeBits(run.extra, run.extraBits) }
            }
        }

        /// Encodes a code-length sequence using repeat codes 16 (copy previous 3-6x), 17 (zero 3-10x),
        /// and 18 (zero 11-138x).
        private static func runLengthEncode(_ lengths: [Int]) -> [(symbol: Int, extra: Int, extraBits: Int)] {
            var out: [(Int, Int, Int)] = []
            var i = 0
            while i < lengths.count {
                let value = lengths[i]
                var runEnd = i + 1
                while runEnd < lengths.count, lengths[runEnd] == value {
                    runEnd += 1
                }
                var run = runEnd - i
                if value == 0 {
                    while run >= 3 {
                        let take = min(run, 138)
                        if take <= 10 { out.append((17, take - 3, 3)) } else { out.append((18, take - 11, 7)) }
                        run -= take
                    }
                    while run > 0 {
                        out.append((0, 0, 0))
                        run -= 1
                    }
                } else {
                    out.append((value, 0, 0))
                    run -= 1
                    while run >= 3 {
                        let take = min(run, 6)
                        out.append((16, take - 3, 2))
                        run -= take
                    }
                    while run > 0 {
                        out.append((value, 0, 0))
                        run -= 1
                    }
                }
                i = runEnd
            }
            return out
        }
    }

    /// Builds length-limited canonical Huffman code lengths from symbol frequencies, by the standard
    /// frequency-merge (T.81 Annex K / RFC 1951) followed by the bit-length-limiting redistribution.
    private static func buildCodeLengths(_ frequencies: [Int], limit: Int) -> [Int] {
        let n = frequencies.count
        let live = (0 ..< n).filter { frequencies[$0] > 0 }
        var lengths = [Int](repeating: 0, count: n)
        if live.isEmpty { return lengths }
        if live.count == 1 { lengths[live[0]] = 1
            return lengths
        } // a lone symbol gets a 1-bit code

        var freq = frequencies
        var codeSize = [Int](repeating: 0, count: n)
        var others = [Int](repeating: -1, count: n)
        while true {
            var c1 = -1, least = Int.max
            for i in 0 ..< n where freq[i] > 0 && freq[i] <= least {
                least = freq[i]
                c1 = i
            }
            var c2 = -1
            least = Int.max
            for i in 0 ..< n where freq[i] > 0 && freq[i] <= least && i != c1 {
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

        // Histogram of pre-limit code lengths (a degenerate distribution can reach n-1 bits).
        var lengthCounts = [Int](repeating: 0, count: n + 1)
        for symbol in 0 ..< n where codeSize[symbol] > 0 {
            lengthCounts[codeSize[symbol]] += 1
        }

        // Push codes longer than the limit back down (RFC 1951 / T.81 Figure K.3).
        var bitLength = n
        while bitLength > limit {
            while lengthCounts[bitLength] > 0 {
                var j = bitLength - 2
                while lengthCounts[j] == 0 {
                    j -= 1
                }
                lengthCounts[bitLength] -= 2
                lengthCounts[bitLength - 1] += 1
                lengthCounts[j + 1] += 2
                lengthCounts[j] -= 1
            }
            bitLength -= 1
        }

        // Assign the limited lengths to symbols shortest-first, preserving the merge's ordering (so
        // the most frequent symbols keep the shortest codes).
        var ordered: [Int] = []
        for length in 1 ... n {
            for symbol in 0 ..< n where codeSize[symbol] == length {
                ordered.append(symbol)
            }
        }
        var assignment: [Int] = []
        for length in 1 ... limit {
            for _ in 0 ..< lengthCounts[length] {
                assignment.append(length)
            }
        }
        for k in 0 ..< ordered.count {
            lengths[ordered[k]] = assignment[k]
        }
        return lengths
    }

    /// Bit-reversed canonical Huffman codes for per-symbol lengths, matching the assignment
    /// ``Inflate`` decodes (ordered by length then symbol). Reversed so the LSB-first writer emits
    /// each code most-significant-bit first, per the spec.
    private static func encodeTable(_ lengths: [Int]) -> [Int] {
        let maxLength = lengths.max() ?? 0
        guard maxLength > 0 else { return [Int](repeating: 0, count: lengths.count) }
        var countByLength = [Int](repeating: 0, count: maxLength + 1)
        for length in lengths where length > 0 {
            countByLength[length] += 1
        }
        var nextCode = [Int](repeating: 0, count: maxLength + 1)
        var code = 0
        for length in 1 ... maxLength {
            code = (code + countByLength[length - 1]) << 1
            nextCode[length] = code
        }
        var codes = [Int](repeating: 0, count: lengths.count)
        for symbol in 0 ..< lengths.count {
            let length = lengths[symbol]
            guard length > 0 else { continue }
            codes[symbol] = reverse(nextCode[length], length)
            nextCode[length] += 1
        }
        return codes
    }

    private static func reverse(_ value: Int, _ width: Int) -> Int {
        var input = value
        var output = 0
        for _ in 0 ..< width {
            output = (output << 1) | (input & 1)
            input >>= 1
        }
        return output
    }

    private static func distanceCodeFor(_ distance: Int) -> Int {
        var code = distanceBase.count - 1
        while code > 0, distanceBase[code] > distance {
            code -= 1
        }
        return code
    }

    // MARK: - Bit writer (LSB-first packing)

    /// Accumulates bits least-significant-first into bytes, as DEFLATE requires. Huffman codes arrive
    /// already bit-reversed (see `encodeTable`), so the same path emits them MSB-first per the spec.
    private struct BitWriter {
        private var bytes: [UInt8] = []
        private var buffer: UInt32 = 0
        private var count = 0

        mutating func writeBits(_ value: Int, _ width: Int) {
            guard width > 0 else { return }
            buffer |= UInt32(value & ((1 << width) - 1)) << count
            count += width
            while count >= 8 {
                bytes.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                count -= 8
            }
        }

        mutating func alignToByte() {
            if count > 0 {
                bytes.append(UInt8(buffer & 0xFF))
                buffer = 0
                count = 0
            }
        }

        mutating func writeBytes(_ raw: [UInt8]) {
            // Stored data is byte-aligned by construction (alignToByte precedes it).
            bytes.append(contentsOf: raw)
        }

        mutating func finish() -> [UInt8] {
            alignToByte()
            return bytes
        }
    }

    // MARK: - Constants

    private static let minMatch = 3
    private static let maxMatch = 258
    private static let windowSize = 32768
    private static let maxChain = 256
    private static let hashBits = 15
    private static let endOfBlock = 256
    private static let literalCount = 286 // literals 0-255, end-of-block 256, length codes 257-285
    private static let distanceCount = 30
    private static let blockTokenLimit = 16384

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtraBits = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtraBits = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// `lengthCodeFor[L]` is the length code (0...28) for a match length L (3...258).
    private static let lengthCodeFor: [Int] = {
        var table = [Int](repeating: 0, count: maxMatch + 1)
        for code in 0 ..< lengthBase.count {
            let upper = lengthBase[code] + (1 << lengthExtraBits[code]) - 1
            for length in lengthBase[code] ... min(upper, maxMatch) {
                table[length] = code
            }
        }
        return table
    }()

    /// Fixed literal/length code lengths: 0-143 = 8, 144-255 = 9, 256-279 = 7, 280-287 = 8.
    private static let fixedLiteralLengths: [Int] = {
        var lengths = [Int](repeating: 8, count: 288)
        for i in 144 ... 255 {
            lengths[i] = 9
        }
        for i in 256 ... 279 {
            lengths[i] = 7
        }
        return lengths
    }()

    private static let fixedLiteralCodes = encodeTable(fixedLiteralLengths)
    private static let fixedDistanceLengths = [Int](repeating: 5, count: 30)
    private static let fixedDistanceCodes = encodeTable([Int](repeating: 5, count: 30))
}
