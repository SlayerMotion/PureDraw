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

    @Test func pageBoxesAreWrittenInPDFCoordinates() throws {
        var context = GraphicsContext()
        context.setFillColor(.black)
        context.addRect(Rect(x: 0, y: 0, width: 10, height: 10))
        context.fillPath()

        let renderer = PDFRenderer(
            width: 100,
            height: 200,
            cropBox: Rect(x: 10, y: 20, width: 50, height: 60),
            trimBox: Rect(x: 0, y: 0, width: 100, height: 200)
        )
        let pdf = try String(decoding: renderer.render(context), as: UTF8.self)

        // User-space (10, 20, 50x60) on a 200-tall page: PDF y runs bottom-up.
        #expect(pdf.contains("/CropBox [ 10.0 120.0 60.0 180.0 ]"))
        #expect(pdf.contains("/TrimBox [ 0.0 0.0 100.0 200.0 ]"))
        #expect(!pdf.contains("/BleedBox"))
        #expect(!pdf.contains("/ArtBox"))
    }

    @Test func drawingTransformFitsAndCenters() {
        // Exact fit: identity.
        let same = PDFRenderer.drawingTransform(
            fitting: Rect(x: 0, y: 0, width: 100, height: 50),
            into: Rect(x: 0, y: 0, width: 100, height: 50)
        )
        #expect(Point(x: 0, y: 0).applying(same) == Point(x: 0, y: 0))
        #expect(Point(x: 100, y: 50).applying(same) == Point(x: 100, y: 50))

        // Shrink to fit, aspect preserved.
        let shrink = PDFRenderer.drawingTransform(
            fitting: Rect(x: 0, y: 0, width: 200, height: 100),
            into: Rect(x: 0, y: 0, width: 100, height: 50)
        )
        #expect(Point(x: 0, y: 0).applying(shrink) == Point(x: 0, y: 0))
        #expect(Point(x: 200, y: 100).applying(shrink) == Point(x: 100, y: 50))

        // Never scales up: a small box is centered, not stretched.
        let centered = PDFRenderer.drawingTransform(
            fitting: Rect(x: 0, y: 0, width: 10, height: 10),
            into: Rect(x: 0, y: 0, width: 100, height: 100)
        )
        #expect(Point(x: 0, y: 0).applying(centered) == Point(x: 45, y: 45))
        #expect(Point(x: 10, y: 10).applying(centered) == Point(x: 55, y: 55))
    }

    @Test func drawingTransformRotatesByQuarterTurns() {
        let transform = PDFRenderer.drawingTransform(
            fitting: Rect(x: 0, y: 0, width: 200, height: 100),
            into: Rect(x: 0, y: 0, width: 100, height: 200),
            rotationDegrees: 90
        )
        let corner = Point(x: 0, y: 0).applying(transform)
        #expect(abs(corner.x - 100) < 1e-9 && abs(corner.y) < 1e-9, "got \(corner)")
        let opposite = Point(x: 200, y: 100).applying(transform)
        #expect(abs(opposite.x) < 1e-9 && abs(opposite.y - 200) < 1e-9, "got \(opposite)")
    }
}
