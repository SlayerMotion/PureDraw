//
//  PDFValueParser.swift
//  PureDraw
//

/// A recursive-descent parser for a single PDF object value at a byte cursor: dictionaries, arrays,
/// names, strings, numbers, indirect references (`N G R`), booleans, and null. It reads only as much
/// as the page model needs; a `stream` after a dictionary is recognized so the dictionary is still
/// returned, but the stream bytes are skipped.
struct PDFValueParser {
    private let data: [UInt8]

    init(_ data: [UInt8]) {
        self.data = data
    }

    /// Parses the value starting at `cursor`, advancing it past the value. Returns `nil` if no value
    /// begins there.
    func parseValue(at cursor: inout Int) -> PDFValue? {
        skipWhitespaceAndComments(&cursor)
        guard cursor < data.count else { return nil }
        let byte = data[cursor]

        switch byte {
        case 0x2F: // '/'
            return .name(parseName(&cursor))
        case 0x28: // '('
            return .string(parseLiteralString(&cursor))
        case 0x5B: // '['
            return parseArray(&cursor)
        case 0x3C: // '<'
            if cursor + 1 < data.count, data[cursor + 1] == 0x3C { return parseDictionaryOrStream(&cursor) }
            return .string(parseHexString(&cursor))
        case 0x74: // 't'
            return matchKeyword("true", &cursor) ? .boolean(true) : nil
        case 0x66: // 'f'
            return matchKeyword("false", &cursor) ? .boolean(false) : nil
        case 0x6E: // 'n'
            return matchKeyword("null", &cursor) ? .null : nil
        case 0x2B, 0x2D, 0x2E, 0x30 ... 0x39: // '+','-','.', digit
            return parseNumberOrReference(&cursor)
        default:
            return nil
        }
    }

    // MARK: Composite values

    private func parseDictionaryOrStream(_ cursor: inout Int) -> PDFValue {
        cursor += 2 // consume '<<'
        var dict: [String: PDFValue] = [:]
        while true {
            skipWhitespaceAndComments(&cursor)
            guard cursor < data.count else { break }
            if data[cursor] == 0x3E, cursor + 1 < data.count, data[cursor + 1] == 0x3E {
                cursor += 2 // consume '>>'
                break
            }
            guard data[cursor] == 0x2F else { cursor += 1
                continue
            } // expect a '/' key
            let key = parseName(&cursor)
            guard let value = parseValue(at: &cursor) else { break }
            dict[key] = value
        }
        // A 'stream' keyword may follow the dictionary, introducing raw bytes up to 'endstream'.
        let saved = cursor
        skipWhitespaceAndComments(&cursor)
        if matchKeyword("stream", &cursor) {
            // The keyword is followed by CR LF or LF, then the data begins.
            if cursor < data.count, data[cursor] == 0x0D { cursor += 1 }
            if cursor < data.count, data[cursor] == 0x0A { cursor += 1 }
            let start = cursor
            skipToKeyword("endstream", &cursor)
            // `cursor` now sits just past 'endstream'; the data ends before it, less the framing EOL.
            var end = cursor - "endstream".count
            if end > start, data[end - 1] == 0x0A { end -= 1 }
            if end > start, data[end - 1] == 0x0D { end -= 1 }
            return .stream(dict, Array(data[start ..< max(start, end)]))
        }
        cursor = saved
        return .dictionary(dict)
    }

    private func parseArray(_ cursor: inout Int) -> PDFValue {
        cursor += 1 // consume '['
        var values: [PDFValue] = []
        while true {
            skipWhitespaceAndComments(&cursor)
            guard cursor < data.count else { break }
            if data[cursor] == 0x5D { cursor += 1
                break
            } // ']'
            guard let value = parseValue(at: &cursor) else { break }
            values.append(value)
        }
        return .array(values)
    }

    // MARK: Scalars

    private func parseName(_ cursor: inout Int) -> String {
        cursor += 1 // consume '/'
        var bytes: [UInt8] = []
        while cursor < data.count, !isWhitespace(data[cursor]), !isDelimiter(data[cursor]) {
            bytes.append(data[cursor])
            cursor += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Parses a number, then looks ahead for `G R` to recognize an indirect reference `N G R`.
    private func parseNumberOrReference(_ cursor: inout Int) -> PDFValue? {
        let start = cursor
        let first = parseNumberToken(&cursor)
        guard let first else { cursor = start
            return nil
        }

        // Only a non-negative integer can begin a reference.
        if first == first.rounded(), first >= 0 {
            let afterFirst = cursor
            skipWhitespaceAndComments(&cursor)
            let generation = parseNumberToken(&cursor)
            if let generation, generation == generation.rounded(), generation >= 0 {
                skipWhitespaceAndComments(&cursor)
                if matchKeyword("R", &cursor) {
                    return .reference(Int(first), Int(generation))
                }
            }
            cursor = afterFirst
        }
        return .number(first)
    }

    private func parseNumberToken(_ cursor: inout Int) -> Double? {
        let start = cursor
        if cursor < data.count, data[cursor] == 0x2B || data[cursor] == 0x2D { cursor += 1 }
        while cursor < data.count, data[cursor] >= 0x30 && data[cursor] <= 0x39 || data[cursor] == 0x2E {
            cursor += 1
        }
        guard cursor > start else { return nil }
        return Double(String(decoding: data[start ..< cursor], as: UTF8.self))
    }

    private func parseLiteralString(_ cursor: inout Int) -> [UInt8] {
        cursor += 1 // consume '('
        var bytes: [UInt8] = []
        var depth = 1
        while cursor < data.count {
            let byte = data[cursor]
            if byte == 0x5C, cursor + 1 < data.count { // backslash escape
                bytes.append(data[cursor + 1])
                cursor += 2
                continue
            }
            if byte == 0x28 { depth += 1 }
            if byte == 0x29 { depth -= 1
                if depth == 0 { cursor += 1
                    break
                }
            }
            bytes.append(byte)
            cursor += 1
        }
        return bytes
    }

    private func parseHexString(_ cursor: inout Int) -> [UInt8] {
        cursor += 1 // consume '<'
        var nibbles: [UInt8] = []
        while cursor < data.count, data[cursor] != 0x3E {
            if let value = hexValue(data[cursor]) { nibbles.append(value) }
            cursor += 1
        }
        if cursor < data.count { cursor += 1 } // consume '>'
        var bytes: [UInt8] = []
        var index = 0
        while index + 1 < nibbles.count {
            bytes.append(nibbles[index] << 4 | nibbles[index + 1])
            index += 2
        }
        if index < nibbles.count { bytes.append(nibbles[index] << 4) }
        return bytes
    }

    // MARK: Lexical helpers

    private func matchKeyword(_ keyword: String, _ cursor: inout Int) -> Bool {
        let bytes = Array(keyword.utf8)
        guard cursor + bytes.count <= data.count, Array(data[cursor ..< cursor + bytes.count]) == bytes else { return false }
        cursor += bytes.count
        return true
    }

    private func skipToKeyword(_ keyword: String, _ cursor: inout Int) {
        let bytes = Array(keyword.utf8)
        while cursor + bytes.count <= data.count {
            if Array(data[cursor ..< cursor + bytes.count]) == bytes { cursor += bytes.count
                return
            }
            cursor += 1
        }
    }

    private func skipWhitespaceAndComments(_ cursor: inout Int) {
        while cursor < data.count {
            if isWhitespace(data[cursor]) { cursor += 1
                continue
            }
            if data[cursor] == 0x25 { // '%' comment to end of line
                while cursor < data.count, data[cursor] != 0x0A, data[cursor] != 0x0D {
                    cursor += 1
                }
                continue
            }
            break
        }
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C || byte == 0x00
    }

    private func isDelimiter(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25: true
        default: false
        }
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30 ... 0x39: byte - 0x30
        case 0x41 ... 0x46: byte - 0x41 + 10
        case 0x61 ... 0x66: byte - 0x61 + 10
        default: nil
        }
    }
}
