//
//  PDFPageRedrawTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
@testable import Renderers
import Testing

/// The full PDF redraw round trip, verified at the pixel level: a scene rendered directly, then
/// written to PDF, read back, replayed through the page's destination transform, and rendered again,
/// produces the same image. This settles the coordinate convention empirically: a PDF page's space is
/// bottom-left-origin (y-up), and `destinationTransform` inverts y so the replay cancels the content's
/// own page-space flip, reproducing the original upright.
struct PDFPageRedrawTests {
    private let side = 60

    private func render(_ context: GraphicsContext) throws -> [UInt8] {
        try BitmapRenderer(width: side, height: side).draw(context).data
    }

    private func meanAbsoluteDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var total = 0.0
        for index in a.indices {
            total += abs(Double(a[index]) - Double(b[index]))
        }
        return total / Double(a.count)
    }

    @Test func filledPathRedrawsToTheSameImage() throws {
        var original = GraphicsContext()
        original.setFillColor(Color(red: 0.85, green: 0.2, blue: 0.3, alpha: 1))
        original.fill(Rect(x: 12, y: 8, width: 30, height: 22))
        let expected = try render(original)

        let data = try PDFRenderer(width: Double(side), height: Double(side)).render(original)
        let page = try #require(PDFDocumentReader().read([UInt8](data))?.pages.first)

        let target = side
        let destination = page.destinationTransform(into: Rect(x: 0, y: 0, width: Double(target), height: Double(target)))
        let replayed = PDFPageInterpreter().interpret(page.content, initialTransform: destination)
        let actual = try render(replayed)

        // The redraw reproduces the original; only rasterizer edge rounding may differ.
        let mad = meanAbsoluteDifference(expected, actual)
        #expect(mad <= 1.0, "redraw mean absolute difference \(mad) exceeds the bound")
        // And it is not trivially blank.
        #expect(actual.contains { $0 != 0 })
    }

    @Test func twoFillsRedrawInPlace() throws {
        var original = GraphicsContext()
        original.setFillColor(Color(red: 0, green: 0, blue: 1, alpha: 1))
        original.fill(Rect(x: 5, y: 5, width: 20, height: 20))
        original.setFillColor(Color(red: 0, green: 1, blue: 0, alpha: 1))
        original.fill(Rect(x: 35, y: 35, width: 18, height: 18))
        let expected = try render(original)

        let data = try PDFRenderer(width: Double(side), height: Double(side)).render(original)
        let page = try #require(PDFDocumentReader().read([UInt8](data))?.pages.first)
        let destination = page.destinationTransform(into: Rect(x: 0, y: 0, width: Double(side), height: Double(side)))
        let actual = try render(PDFPageInterpreter().interpret(page.content, initialTransform: destination))

        #expect(meanAbsoluteDifference(expected, actual) <= 1.0)
    }
}
