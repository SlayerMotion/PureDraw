//
//  PDFValue.swift
//  PureDraw
//

/// A value in a PDF object, enough of the model to read the page tree: numbers, names, strings,
/// arrays, dictionaries, indirect references, booleans, and null.
indirect enum PDFValue: Equatable {
    case number(Double)
    case name(String)
    case string([UInt8])
    case array([PDFValue])
    case dictionary([String: PDFValue])
    case reference(Int, Int)
    case boolean(Bool)
    case null

    var numberValue: Double? {
        if case let .number(value) = self { value } else { nil }
    }

    var dictionaryValue: [String: PDFValue]? {
        if case let .dictionary(dict) = self { dict } else { nil }
    }

    var arrayValue: [PDFValue]? {
        if case let .array(values) = self { values } else { nil }
    }

    var nameValue: String? {
        if case let .name(name) = self { name } else { nil }
    }
}
