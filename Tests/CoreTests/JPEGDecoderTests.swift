//
//  JPEGDecoderTests.swift
//  PureDraw
//
//  Hermetic, dependency-free coverage of the baseline JPEG pipeline. Each case hand-builds a
//  minimal valid grayscale JFIF (SOI / DQT / SOF0 / DHT / SOS / one entropy-coded MCU / EOI)
//  whose single 8x8 block carries only a DC coefficient, so the inverse DCT produces a known
//  flat color. This exercises marker parsing, canonical Huffman DECODE, the sign-extend of both
//  positive and negative coefficients, dequantization, and the level-shifted IDCT without any
//  platform codec. Lossy AC, chroma, and subsampling paths are checked against ImageIO in
//  RenderersTests/JPEGDecoderOracleTests.
//

@testable import Core
import Testing

struct JPEGDecoderTests {
    /// Accumulates bits MSB-first into entropy bytes, applying JPEG `FF -> FF 00` stuffing and
    /// padding the final byte with 1-bits, exactly as an encoder would.
    private struct BitWriter {
        private var bytes: [UInt8] = []
        private var current: UInt8 = 0
        private var filled = 0

        mutating func write(_ value: Int, bits: Int) {
            var bit = bits - 1
            while bit >= 0 {
                append((value >> bit) & 1)
                bit -= 1
            }
        }

        private mutating func append(_ bit: Int) {
            current = (current << 1) | UInt8(bit & 1)
            filled += 1
            if filled == 8 { flushByte() }
        }

        private mutating func flushByte() {
            bytes.append(current)
            if current == 0xFF { bytes.append(0x00) } // byte stuffing
            current = 0
            filled = 0
        }

        mutating func finish() -> [UInt8] {
            if filled > 0 {
                current = (current << (8 - filled)) | UInt8((1 << (8 - filled)) - 1) // pad with 1s
                filled = 8
                flushByte()
            }
            return bytes
        }
    }

    /// Builds a complete 8x8 single-block grayscale baseline JPEG whose flat value is `gray`.
    private func flatGrayJPEG(gray: Int) -> [UInt8] {
        var data: [UInt8] = [0xFF, 0xD8] // SOI

        // DQT: table 0, 8-bit precision, all coefficients 1 (no quantization loss).
        data += [0xFF, 0xDB, 0x00, 0x43, 0x00]
        data += [UInt8](repeating: 1, count: 64)

        // SOF0: 8x8, one component (id 1, 1x1 sampling, quant table 0).
        data += [0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x08, 0x00, 0x08, 0x01, 0x01, 0x11, 0x00]

        // DHT DC table 0: symbols 8 and 10, both 2-bit codes ("00" -> 8, "01" -> 10).
        data += [0xFF, 0xC4, 0x00, 0x15, 0x00]
        data += [0x00, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] // BITS
        data += [0x08, 0x0A] // HUFFVAL

        // DHT AC table 0: a single 1-bit code ("0") for EOB (symbol 0x00).
        data += [0xFF, 0xC4, 0x00, 0x14, 0x10]
        data += [0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] // BITS
        data += [0x00] // HUFFVAL

        // SOS: one component (id 1, DC table 0, AC table 0), spectral selection 0..63.
        data += [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00]

        // Entropy: DC coefficient that level-shifts to `gray`, then EOB.
        let dcCoefficient = (gray - 128) * 8 // F(0,0); IDCT of a DC-only block is F(0,0)/8 + 128
        let category = dcCoefficient == 0 ? 0 : magnitudeBits(abs(dcCoefficient))
        var writer = BitWriter()
        // DC Huffman code: "00" for category 8, "01" for category 10.
        switch category {
        case 8: writer.write(0b00, bits: 2)
        case 10: writer.write(0b01, bits: 2)
        default: Issue.record("test fixture only models categories 8 and 10, got \(category)")
        }
        if category > 0 {
            let stored = dcCoefficient > 0 ? dcCoefficient : dcCoefficient + (1 << category) - 1
            writer.write(stored, bits: category)
        }
        writer.write(0b0, bits: 1) // AC EOB
        data += writer.finish()

        data += [0xFF, 0xD9] // EOI
        return data
    }

    private func magnitudeBits(_ value: Int) -> Int {
        var bits = 0
        var v = value
        while v > 0 {
            bits += 1
            v >>= 1
        }
        return bits
    }

    /// Grays chosen so the DC coefficient lands in Huffman category 8 or 10, the two the minimal
    /// fixture table models: 100 -> -224, 150 -> 176, 200 -> 576, 192 -> 512, 60 -> -544.
    @Test(arguments: [100, 150, 200, 192, 60])
    func decodesFlatGrayscale(gray: Int) throws {
        let jpeg = flatGrayJPEG(gray: gray)
        let image = try ImageDecoder.decode(jpeg)
        #expect(image.width == 8 && image.height == 8)
        #expect(image.alphaInfo == .last)

        let expected = UInt8(gray)
        var mismatches = 0
        for pixel in 0 ..< image.width * image.height {
            let dst = pixel * 4
            if image.data[dst] != expected || image.data[dst + 1] != expected
                || image.data[dst + 2] != expected || image.data[dst + 3] != 255
            {
                mismatches += 1
            }
        }
        #expect(mismatches == 0, "every pixel should be opaque gray \(expected)")
    }

    @Test func reportsProgressiveAsUnsupported() {
        // A frame header with the SOF2 (progressive) marker must be rejected, not guessed.
        var data: [UInt8] = [0xFF, 0xD8]
        data += [0xFF, 0xC2, 0x00, 0x0B, 0x08, 0x00, 0x08, 0x00, 0x08, 0x01, 0x11, 0x00]
        data += [0xFF, 0xD9]
        #expect(throws: ImageDecoder.Error.unsupportedFormat("progressive JPEG")) {
            try ImageDecoder.decode(data)
        }
    }

    @Test func reportsTruncatedStreamAsMalformed() {
        // SOI followed by a DQT that claims more bytes than are present.
        let data: [UInt8] = [0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x01, 0x02]
        #expect(throws: ImageDecoder.Error.self) {
            try ImageDecoder.decode(data)
        }
    }

    /// Malformed/crafted inputs must surface a catchable `ImageDecoder.Error`, never trap the
    /// process. Each case here would index out of bounds, divide by zero, overflow a shift, or
    /// request a huge allocation if the decoder trusted the header; the test passing at all (no
    /// crash) is the proof, and `#expect(throws:)` pins the recoverable contract.
    @Test(arguments: [
        [0xFF, 0xD8, 0xFF, 0xDB], // marker with no room for a length word
        [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x08, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00], // sampling factor 0 -> div-by-zero
        [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x01, 0x11, 0x00], // 65535x65535 -> oversized allocation
        [0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x08, 0xFF, 0x01, 0x00, 0x00, 0x3F, 0x00], // SOS scanCount 255 overruns header
        [0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02], // minimal SOS at EOF: scanCount byte would read past the buffer
        [0xFF, 0xD8, 0xFF, 0xEE, 0x00, 0x0E, 0x41, 0x64], // APP14 length claims 14 bytes, only 2 present
        [0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x03, 0x20], // DQT precision nibble 2 (neither 8- nor 16-bit)
    ] as [[UInt8]])
    func rejectsMalformedWithoutTrapping(bytes: [UInt8]) {
        #expect(throws: ImageDecoder.Error.self) {
            try ImageDecoder.decode(bytes)
        }
    }
}
