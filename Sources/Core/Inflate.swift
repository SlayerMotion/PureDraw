//
//  Inflate.swift
//  PureDraw
//

/// A dependency-free DEFLATE (RFC 1951) decompressor, with a zlib (RFC 1950) wrapper. The
/// counterpart to `PNGEncoder`'s zlib writer: the inflate half needed to decode PNG `IDAT`
/// streams (and any FlateDecode data). Returns nil on malformed input rather than trapping.
///
/// The Huffman decoder uses the canonical-code accumulation from zlib's reference `puff.c`:
/// symbols are sorted by (code length, symbol) and decoded by reading one bit at a time,
/// comparing the accumulated code against the first code of each length.
enum Inflate {
    /// Decompresses a zlib stream: a 2-byte header, the DEFLATE body, and a trailing Adler-32.
    /// The header and checksum are validated; returns nil if either is malformed.
    static func zlib(_ input: [UInt8]) -> [UInt8]? {
        guard input.count >= 6 else { return nil }
        // CMF/FLG: low nibble of CMF must be 8 (deflate); (CMF<<8 | FLG) must be a multiple of
        // 31; bit 5 of FLG (preset dictionary) is not supported.
        let cmf = Int(input[0]), flg = Int(input[1])
        guard cmf & 0x0F == 8, (cmf << 8 | flg) % 31 == 0, flg & 0x20 == 0 else { return nil }
        guard let output = deflate(Array(input[2 ..< input.count - 4])) else { return nil }
        let expected = UInt32(input[input.count - 4]) << 24 | UInt32(input[input.count - 3]) << 16
            | UInt32(input[input.count - 2]) << 8 | UInt32(input[input.count - 1])
        guard adler32(output) == expected else { return nil }
        return output
    }

    /// Decompresses a raw DEFLATE stream (no zlib wrapper). Returns nil on malformed input.
    static func deflate(_ input: [UInt8]) -> [UInt8]? {
        var reader = BitReader(input)
        var output: [UInt8] = []

        while true {
            guard let final = reader.bit() else { return nil }
            guard let type = reader.bits(2) else { return nil }
            switch type {
            case 0:
                if !inflateStored(&reader, &output) { return nil }
            case 1:
                if !inflateBlock(&reader, &output, lengths: Self.fixedLiteralTable, distances: Self.fixedDistanceTable) { return nil }
            case 2:
                guard let (lit, dist) = readDynamicTables(&reader) else { return nil }
                if !inflateBlock(&reader, &output, lengths: lit, distances: dist) { return nil }
            default:
                return nil // reserved block type
            }
            if final == 1 { return output }
        }
    }

    // MARK: - Block types

    private static func inflateStored(_ reader: inout BitReader, _ output: inout [UInt8]) -> Bool {
        reader.alignToByte()
        guard let len = reader.uint16LE(), let nlen = reader.uint16LE() else { return false }
        guard len == (~nlen & 0xFFFF) else { return false } // LEN and its one's-complement must agree
        for _ in 0 ..< len {
            guard let byte = reader.byte() else { return false }
            output.append(byte)
        }
        return true
    }

    /// Decodes a Huffman-coded block (fixed or dynamic) into `output`, copying back-references
    /// from the already-decoded bytes.
    private static func inflateBlock(_ reader: inout BitReader, _ output: inout [UInt8], lengths: Huffman, distances: Huffman) -> Bool {
        while true {
            guard let sym = lengths.decode(&reader) else { return false }
            if sym == 256 { return true } // end of block
            if sym < 256 {
                output.append(UInt8(sym))
                continue
            }
            // Length code (257...285): a base length plus extra bits.
            let li = sym - 257
            guard li < Self.lengthBase.count else { return false }
            guard let lengthExtra = reader.bits(Self.lengthExtraBits[li]) else { return false }
            let length = Self.lengthBase[li] + lengthExtra
            // Distance code: a base distance plus extra bits.
            guard let distSym = distances.decode(&reader), distSym < Self.distanceBase.count else { return false }
            guard let distExtra = reader.bits(Self.distanceExtraBits[distSym]) else { return false }
            let distance = Self.distanceBase[distSym] + distExtra
            guard distance >= 1, distance <= output.count else { return false }
            // Copy `length` bytes from `distance` back; the run may overlap (distance < length),
            // which repeats the tail, so copy one byte at a time.
            var src = output.count - distance
            for _ in 0 ..< length {
                output.append(output[src])
                src += 1
            }
        }
    }

    /// Reads a dynamic block's two Huffman tables (literal/length and distance) from the
    /// code-length code that precedes them (RFC 1951 §3.2.7).
    private static func readDynamicTables(_ reader: inout BitReader) -> (Huffman, Huffman)? {
        guard let hlit = reader.bits(5), let hdist = reader.bits(5), let hclen = reader.bits(4) else { return nil }
        let numLit = hlit + 257, numDist = hdist + 1, numCodeLen = hclen + 4

        // Code-length code lengths, read in the permuted order.
        var clLengths = [Int](repeating: 0, count: 19)
        for i in 0 ..< numCodeLen {
            guard let l = reader.bits(3) else { return nil }
            clLengths[Self.codeLengthOrder[i]] = l
        }
        let clHuffman = Huffman(codeLengths: clLengths)

        // Decode the literal/length and distance code lengths as one run, honoring the
        // repeat codes: 16 (repeat previous 3-6x), 17 (zero 3-10x), 18 (zero 11-138x).
        var lengths: [Int] = []
        lengths.reserveCapacity(numLit + numDist)
        while lengths.count < numLit + numDist {
            guard let sym = clHuffman.decode(&reader) else { return nil }
            switch sym {
            case 0 ... 15:
                lengths.append(sym)
            case 16:
                guard let extra = reader.bits(2), let prev = lengths.last else { return nil }
                lengths.append(contentsOf: Array(repeating: prev, count: 3 + extra))
            case 17:
                guard let extra = reader.bits(3) else { return nil }
                lengths.append(contentsOf: Array(repeating: 0, count: 3 + extra))
            case 18:
                guard let extra = reader.bits(7) else { return nil }
                lengths.append(contentsOf: Array(repeating: 0, count: 11 + extra))
            default:
                return nil
            }
        }
        guard lengths.count == numLit + numDist else { return nil } // a repeat must not overrun
        let lit = Huffman(codeLengths: Array(lengths[0 ..< numLit]))
        let dist = Huffman(codeLengths: Array(lengths[numLit ..< numLit + numDist]))
        return (lit, dist)
    }

    // MARK: - Bit reader

    private struct BitReader {
        private let bytes: [UInt8]
        private var pos = 0
        private var bitBuffer = 0
        private var bitCount = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        /// Reads one bit (DEFLATE packs bits LSB-first within each byte).
        mutating func bit() -> Int? {
            if bitCount == 0 {
                guard pos < bytes.count else { return nil }
                bitBuffer = Int(bytes[pos])
                pos += 1
                bitCount = 8
            }
            let b = bitBuffer & 1
            bitBuffer >>= 1
            bitCount -= 1
            return b
        }

        /// Reads `count` bits, least-significant bit first.
        mutating func bits(_ count: Int) -> Int? {
            var value = 0
            for i in 0 ..< count {
                guard let b = bit() else { return nil }
                value |= b << i
            }
            return value
        }

        mutating func alignToByte() {
            bitCount = 0
        }

        mutating func byte() -> UInt8? {
            guard pos < bytes.count else { return nil }
            defer { pos += 1 }
            return bytes[pos]
        }

        mutating func uint16LE() -> Int? {
            guard let lo = byte(), let hi = byte() else { return nil }
            return Int(lo) | Int(hi) << 8
        }
    }

    // MARK: - Huffman

    /// A canonical Huffman decoder built from per-symbol code lengths.
    private struct Huffman {
        private let counts: [Int] // counts[len] = number of symbols with that code length
        private let symbols: [Int] // symbols sorted by (length, symbol)
        private let maxBits: Int

        init(codeLengths: [Int]) {
            let maxBits = max(0, codeLengths.max() ?? 0)
            guard maxBits > 0 else { // an empty table decodes nothing; decode() guards on this
                counts = [0]
                symbols = []
                self.maxBits = 0
                return
            }
            var counts = [Int](repeating: 0, count: maxBits + 1)
            for l in codeLengths where l > 0 {
                counts[l] += 1
            }
            // Offsets of each length's run within the sorted symbol array.
            var offsets = [Int](repeating: 0, count: maxBits + 2)
            for l in 1 ... maxBits {
                offsets[l + 1] = offsets[l] + counts[l]
            }
            var symbols = [Int](repeating: 0, count: offsets[maxBits + 1])
            for (symbol, l) in codeLengths.enumerated() where l > 0 {
                symbols[offsets[l]] = symbol
                offsets[l] += 1
            }
            self.counts = counts
            self.symbols = symbols
            self.maxBits = maxBits
        }

        /// Decodes one symbol by accumulating bits until the code matches a length's range.
        func decode(_ reader: inout BitReader) -> Int? {
            guard maxBits > 0 else { return nil }
            var code = 0, first = 0, index = 0
            for len in 1 ... maxBits {
                guard let b = reader.bit() else { return nil }
                code |= b
                let count = counts[len]
                if code - first < count { return symbols[index + (code - first)] }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            return nil
        }
    }

    // MARK: - Tables (RFC 1951 §3.2.5, §3.2.6, §3.2.7)

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtraBits = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtraBits = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// Fixed literal/length code lengths: 0-143 = 8 bits, 144-255 = 9, 256-279 = 7, 280-287 = 8.
    private static let fixedLiteralTable: Huffman = {
        var lengths = [Int](repeating: 8, count: 288)
        for i in 144 ... 255 {
            lengths[i] = 9
        }
        for i in 256 ... 279 {
            lengths[i] = 7
        }
        return Huffman(codeLengths: lengths)
    }()

    /// Fixed distance codes: all 5 bits.
    private static let fixedDistanceTable = Huffman(codeLengths: [Int](repeating: 5, count: 30))

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }
}
