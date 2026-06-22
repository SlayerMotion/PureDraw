//
//  PDFValue.swift
//  PureDraw
//

/// A value in a PDF object, enough of the model to read the page tree and a page's content: numbers,
/// names, strings, arrays, dictionaries, streams (a dictionary with attached bytes), indirect
/// references, booleans, and null.
indirect enum PDFValue: Equatable {
    case number(Double)
    case name(String)
    case string([UInt8])
    case array([PDFValue])
    case dictionary([String: PDFValue])
    case stream([String: PDFValue], [UInt8])
    case reference(Int, Int)
    case boolean(Bool)
    case null

    var numberValue: Double? {
        if case let .number(value) = self { value } else { nil }
    }

    /// The dictionary of a dictionary or of a stream (a stream is a dictionary with attached bytes).
    var dictionaryValue: [String: PDFValue]? {
        switch self {
        case let .dictionary(dict): dict
        case let .stream(dict, _): dict
        default: nil
        }
    }

    var arrayValue: [PDFValue]? {
        if case let .array(values) = self { values } else { nil }
    }

    var nameValue: String? {
        if case let .name(name) = self { name } else { nil }
    }

    /// The raw bytes of a stream object, if this value is one.
    var streamBytes: [UInt8]? {
        if case let .stream(_, bytes) = self { bytes } else { nil }
    }
}
