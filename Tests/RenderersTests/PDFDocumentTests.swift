//
//  PDFDocumentTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
@testable import Renderers
import Testing

struct PDFDocumentTests {
    @Test func rootReferencesTheCatalogEvenWithImages() throws {
        let sprite = try Image(width: 2, height: 2, data: [UInt8](repeating: 255, count: 16))

        var context = GraphicsContext()
        context.draw(sprite, in: Rect(x: 0, y: 0, width: 10, height: 10))
        context.setFillColor(.black)
        context.addRect(Rect(x: 0, y: 0, width: 5, height: 5))
        context.fillPath()

        let pdf = try String(decoding: PDFRenderer(width: 100, height: 100).render(context), as: UTF8.self)

        let rootID = try #require(captureInt(in: pdf, pattern: "/Root ", suffix: " 0 R"))
        #expect(pdf.contains("\(rootID) 0 obj\n<< /Type /Catalog"), "the /Root reference must point at the catalog object")
    }

    /// Extracts the integer between `pattern` and `suffix`.
    func captureInt(in text: String, pattern: String, suffix: String) -> Int? {
        guard let patternRange = text.range(of: pattern) else { return nil }
        let tail = text[patternRange.upperBound...]
        guard let suffixRange = tail.range(of: suffix) else { return nil }
        return Int(tail[..<suffixRange.lowerBound])
    }
}
