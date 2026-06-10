//
//  PDFScanner.swift
//  PureDraw
//

import Core

/// Tokenizes a PDF content stream and invokes registered operator callbacks
/// with their operands, the `CGPDFScanner` equivalent. Operands accumulate on
/// a stack until an operator token arrives; unregistered operators consume
/// their operands silently.
public struct PDFScanner {
    /// A parsed content-stream object.
    public indirect enum Operand: Equatable, Sendable {
        case integer(Int)
        case real(Double)
        case boolean(Bool)
        case string([UInt8])
        case name(String)
        case array([Operand])
        case dictionary([String: Operand])
        case null

        /// The numeric value of an integer or real operand.
        public var numberValue: Double? {
            switch self {
            case let .integer(value): Double(value)
            case let .real(value): value
            default: nil
            }
        }
    }

    public typealias Handler = (_ operands: [Operand]) -> Void

    private var handlers: [String: Handler] = [:]

    public init() {}

    /// Registers a callback for a content-stream operator such as `m`, `re`,
    /// or `Do`. The callback receives the operand stack in source order.
    public mutating func setHandler(forOperator name: String, _ handler: @escaping Handler) {
        handlers[name] = handler
    }

    public func scan(_ content: String) {
        scan(Array(content.utf8))
    }

    /// Scans raw content-stream bytes, dispatching operators in order.
    public func scan(_ content: [UInt8]) {
        var cursor = 0
        var stack: [Operand] = []

        while cursor < content.count {
            skipWhitespaceAndComments(content, &cursor)
            guard cursor < content.count else { break }

            if let operand = parseOperand(content, &cursor) {
                stack.append(operand)
                continue
            }

            guard let token = parseToken(content, &cursor) else { break }
            if token == "true" {
                stack.append(.boolean(true))
            } else if token == "false" {
                stack.append(.boolean(false))
            } else if token == "null" {
                stack.append(.null)
            } else {
                handlers[token]?(stack)
                stack.removeAll(keepingCapacity: true)
            }
        }
    }

    // MARK: - Object Parsing

    private func parseOperand(_ bytes: [UInt8], _ cursor: inout Int) -> Operand? {
        switch bytes[cursor] {
        case UInt8(ascii: "/"):
            cursor += 1
            return .name(parseToken(bytes, &cursor) ?? "")

        case UInt8(ascii: "("):
            return parseLiteralString(bytes, &cursor)

        case UInt8(ascii: "<"):
            if cursor + 1 < bytes.count, bytes[cursor + 1] == UInt8(ascii: "<") {
                return parseDictionary(bytes, &cursor)
            }
            return parseHexString(bytes, &cursor)

        case UInt8(ascii: "["):
            return parseArray(bytes, &cursor)

        case UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "."),
             UInt8(ascii: "0") ... UInt8(ascii: "9"):
            return parseNumber(bytes, &cursor)

        default:
            return nil
        }
    }

    private func parseNumber(_ bytes: [UInt8], _ cursor: inout Int) -> Operand? {
        let start = cursor
        var sawDot = false
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if byte == UInt8(ascii: ".") {
                sawDot = true
                cursor += 1
            } else if byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") || (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte) {
                cursor += 1
            } else {
                break
            }
        }
        let text = String(decoding: bytes[start ..< cursor], as: UTF8.self)
        if sawDot {
            guard let value = Double(text) else { return nil }
            return .real(value)
        }
        guard let value = Int(text) else { return nil }
        return .integer(value)
    }

    private func parseLiteralString(_ bytes: [UInt8], _ cursor: inout Int) -> Operand {
        cursor += 1 // consume "("
        var result: [UInt8] = []
        var depth = 1
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if byte == UInt8(ascii: "\\"), cursor + 1 < bytes.count {
                let escaped = bytes[cursor + 1]
                switch escaped {
                case UInt8(ascii: "n"): result.append(10)
                case UInt8(ascii: "r"): result.append(13)
                case UInt8(ascii: "t"): result.append(9)
                case UInt8(ascii: "b"): result.append(8)
                case UInt8(ascii: "f"): result.append(12)
                default: result.append(escaped)
                }
                cursor += 2
                continue
            }
            if byte == UInt8(ascii: "(") {
                depth += 1
            } else if byte == UInt8(ascii: ")") {
                depth -= 1
                if depth == 0 {
                    cursor += 1
                    break
                }
            }
            result.append(byte)
            cursor += 1
        }
        return .string(result)
    }

    private func parseHexString(_ bytes: [UInt8], _ cursor: inout Int) -> Operand {
        cursor += 1 // consume "<"
        var digits: [UInt8] = []
        while cursor < bytes.count, bytes[cursor] != UInt8(ascii: ">") {
            let byte = bytes[cursor]
            if let value = hexValue(byte) {
                digits.append(value)
            }
            cursor += 1
        }
        if cursor < bytes.count {
            cursor += 1 // consume ">"
        }
        if digits.count % 2 == 1 {
            digits.append(0)
        }
        var result: [UInt8] = []
        for index in stride(from: 0, to: digits.count, by: 2) {
            result.append(digits[index] << 4 | digits[index + 1])
        }
        return .string(result)
    }

    private func parseArray(_ bytes: [UInt8], _ cursor: inout Int) -> Operand {
        cursor += 1 // consume "["
        var elements: [Operand] = []
        while cursor < bytes.count {
            skipWhitespaceAndComments(bytes, &cursor)
            guard cursor < bytes.count else { break }
            if bytes[cursor] == UInt8(ascii: "]") {
                cursor += 1
                break
            }
            if let operand = parseOperand(bytes, &cursor) {
                elements.append(operand)
            } else if let token = parseToken(bytes, &cursor) {
                if token == "true" { elements.append(.boolean(true)) }
                else if token == "false" { elements.append(.boolean(false)) }
                else if token == "null" { elements.append(.null) }
            } else {
                break
            }
        }
        return .array(elements)
    }

    private func parseDictionary(_ bytes: [UInt8], _ cursor: inout Int) -> Operand {
        cursor += 2 // consume "<<"
        var entries: [String: Operand] = [:]
        while cursor < bytes.count {
            skipWhitespaceAndComments(bytes, &cursor)
            guard cursor < bytes.count else { break }
            if cursor + 1 < bytes.count, bytes[cursor] == UInt8(ascii: ">"), bytes[cursor + 1] == UInt8(ascii: ">") {
                cursor += 2
                break
            }
            guard bytes[cursor] == UInt8(ascii: "/") else {
                cursor += 1
                continue
            }
            cursor += 1
            let key = parseToken(bytes, &cursor) ?? ""
            skipWhitespaceAndComments(bytes, &cursor)
            guard cursor < bytes.count else { break }
            if let value = parseOperand(bytes, &cursor) {
                entries[key] = value
            } else if let token = parseToken(bytes, &cursor) {
                if token == "true" { entries[key] = .boolean(true) }
                else if token == "false" { entries[key] = .boolean(false) }
                else if token == "null" { entries[key] = .null }
            }
        }
        return .dictionary(entries)
    }

    // MARK: - Lexing

    private func skipWhitespaceAndComments(_ bytes: [UInt8], _ cursor: inout Int) {
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if isWhitespace(byte) {
                cursor += 1
            } else if byte == UInt8(ascii: "%") {
                while cursor < bytes.count, bytes[cursor] != 10, bytes[cursor] != 13 {
                    cursor += 1
                }
            } else {
                break
            }
        }
    }

    private func parseToken(_ bytes: [UInt8], _ cursor: inout Int) -> String? {
        let start = cursor
        while cursor < bytes.count, !isWhitespace(bytes[cursor]), !isDelimiter(bytes[cursor]) {
            cursor += 1
        }
        if cursor == start {
            cursor += 1 // never stall on a stray delimiter
            return nil
        }
        return String(decoding: bytes[start ..< cursor], as: UTF8.self)
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
    }

    private func isDelimiter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "<"), UInt8(ascii: ">"),
             UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: "{"), UInt8(ascii: "}"),
             UInt8(ascii: "/"), UInt8(ascii: "%"):
            true
        default:
            false
        }
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
