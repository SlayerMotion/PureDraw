//
//  PDFDocumentReader.swift
//  PureDraw
//

import Core
import Geometry

/// Parses a PDF file's bytes into a ``PDFDocument`` page model: read the indirect objects, find the
/// catalog through the trailer (or by type), walk the page tree, and resolve each page's box rects
/// (inheriting `MediaBox` and `CropBox` from ancestor `Pages` nodes, as the format requires).
public struct PDFDocumentReader {
    public init() {}

    /// Reads the page model, or `nil` when the bytes are not a recognizable single- or multi-page PDF.
    public func read(_ data: [UInt8]) -> PDFDocument? {
        guard data.count > 8 else { return nil }
        let objects = parseIndirectObjects(data)
        guard !objects.isEmpty else { return nil }

        // The catalog: via the trailer's /Root if present, else the object typed /Catalog.
        guard let catalog = catalogDictionary(data, objects: objects),
              case let .reference(num, gen)? = catalog["Pages"],
              let pagesRoot = objects[PDFObjectKey(num, gen)]?.dictionaryValue
        else { return nil }

        var pages: [PDFDocument.Page] = []
        collectPages(node: pagesRoot, inheritedMedia: nil, inheritedCrop: nil, objects: objects, into: &pages)
        guard !pages.isEmpty else { return nil }
        return PDFDocument(pages: pages)
    }

    // MARK: Page tree

    /// Depth-first over the page tree, accumulating leaf pages. `Pages` nodes pass their `MediaBox` /
    /// `CropBox` down as inheritable defaults; `Page` leaves resolve their boxes against them.
    private func collectPages(
        node: [String: PDFValue],
        inheritedMedia: Rect?,
        inheritedCrop: Rect?,
        objects: [PDFObjectKey: PDFValue],
        into pages: inout [PDFDocument.Page]
    ) {
        let media = rect(node["MediaBox"], objects: objects) ?? inheritedMedia
        let crop = rect(node["CropBox"], objects: objects) ?? inheritedCrop

        if node["Type"]?.nameValue == "Page" || node["Kids"] == nil {
            let mediaBox = media ?? .zero
            let content = contentBytes(node["Contents"], objects: objects)
            pages.append(PDFDocument.Page(mediaBox: mediaBox, cropBox: crop ?? mediaBox, content: content))
            return
        }

        guard let kids = node["Kids"]?.arrayValue else { return }
        for kid in kids {
            guard case let .reference(num, gen) = kid,
                  let child = objects[PDFObjectKey(num, gen)]?.dictionaryValue else { continue }
            collectPages(node: child, inheritedMedia: media, inheritedCrop: crop, objects: objects, into: &pages)
        }
    }

    /// Resolves a page's `/Contents` to its concatenated content-stream bytes. `/Contents` is either a
    /// stream reference or an array of stream references, which are joined with a newline so operators
    /// split across streams still tokenize, as the format requires.
    private func contentBytes(_ value: PDFValue?, objects: [PDFObjectKey: PDFValue]) -> [UInt8] {
        let resolved = resolve(value, objects: objects)
        if let bytes = resolved?.streamBytes { return bytes }
        guard let elements = resolved?.arrayValue else { return [] }
        var bytes: [UInt8] = []
        for element in elements {
            guard let streamBytes = resolve(element, objects: objects)?.streamBytes else { continue }
            if !bytes.isEmpty { bytes.append(0x0A) }
            bytes.append(contentsOf: streamBytes)
        }
        return bytes
    }

    /// Resolves a value (possibly an indirect reference) to a rectangle from a four-number array.
    private func rect(_ value: PDFValue?, objects: [PDFObjectKey: PDFValue]) -> Rect? {
        let resolved = resolve(value, objects: objects)
        guard let numbers = resolved?.arrayValue, numbers.count == 4 else { return nil }
        let coordinates = numbers.compactMap(\.numberValue)
        guard coordinates.count == 4 else { return nil }
        let x0 = coordinates[0], y0 = coordinates[1], x1 = coordinates[2], y1 = coordinates[3]
        return Rect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
    }

    private func resolve(_ value: PDFValue?, objects: [PDFObjectKey: PDFValue]) -> PDFValue? {
        if case let .reference(num, gen)? = value { return objects[PDFObjectKey(num, gen)] }
        return value
    }

    // MARK: Trailer / catalog

    private func catalogDictionary(_ data: [UInt8], objects: [PDFObjectKey: PDFValue]) -> [String: PDFValue]? {
        if let root = trailerRoot(data), let catalog = objects[root]?.dictionaryValue { return catalog }
        // Fallback: the object explicitly typed /Catalog.
        for value in objects.values where value.dictionaryValue?["Type"]?.nameValue == "Catalog" {
            return value.dictionaryValue
        }
        return nil
    }

    /// The `/Root` reference from the last `trailer` dictionary, if present.
    private func trailerRoot(_ data: [UInt8]) -> PDFObjectKey? {
        let keyword: [UInt8] = Array("trailer".utf8)
        guard let start = lastIndex(of: keyword, in: data) else { return nil }
        var cursor = start + keyword.count
        guard let value = PDFValueParser(data).parseValue(at: &cursor), let dict = value.dictionaryValue,
              case let .reference(num, gen)? = dict["Root"]
        else { return nil }
        return PDFObjectKey(num, gen)
    }

    // MARK: Indirect objects

    /// Parses every `N G obj <value> endobj` definition into an object table keyed by number and
    /// generation. Scanning for the `obj` keyword is robust to xref-table quirks and is sufficient for
    /// the structural model.
    private func parseIndirectObjects(_ data: [UInt8]) -> [PDFObjectKey: PDFValue] {
        var objects: [PDFObjectKey: PDFValue] = [:]
        let parser = PDFValueParser(data)
        let objKeyword: [UInt8] = Array(" obj".utf8)
        var searchStart = 0
        while let objAt = firstIndex(of: objKeyword, in: data, from: searchStart) {
            // Walk back over the two integers (generation then object number) preceding " obj".
            if let (number, generation) = integersBefore(objAt, in: data) {
                var cursor = objAt + objKeyword.count
                if let value = parser.parseValue(at: &cursor) {
                    objects[PDFObjectKey(number, generation)] = value
                }
            }
            searchStart = objAt + objKeyword.count
        }
        return objects
    }

    /// Reads the two whitespace-separated integers ending just before `index` (the object number and
    /// generation in `N G obj`).
    private func integersBefore(_ index: Int, in data: [UInt8]) -> (number: Int, generation: Int)? {
        var cursor = index
        func skipSpacesBack() {
            while cursor > 0, isWhitespace(data[cursor - 1]) {
                cursor -= 1
            }
        }
        func readIntBack() -> Int? {
            let end = cursor
            while cursor > 0, data[cursor - 1] >= 0x30, data[cursor - 1] <= 0x39 {
                cursor -= 1
            }
            guard cursor < end else { return nil }
            return Int(String(decoding: data[cursor ..< end], as: UTF8.self))
        }
        skipSpacesBack()
        guard let generation = readIntBack() else { return nil }
        skipSpacesBack()
        guard let number = readIntBack() else { return nil }
        return (number, generation)
    }

    // MARK: Byte search helpers

    private func firstIndex(of needle: [UInt8], in haystack: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        var i = max(0, from)
        let last = haystack.count - needle.count
        while i <= last {
            if Array(haystack[i ..< i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }

    private func lastIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        var i = haystack.count - needle.count
        while i >= 0 {
            if Array(haystack[i ..< i + needle.count]) == needle { return i }
            i -= 1
        }
        return nil
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C || byte == 0x00
    }
}
