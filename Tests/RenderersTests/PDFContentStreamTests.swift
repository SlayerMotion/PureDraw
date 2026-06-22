//
//  PDFContentStreamTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
import Renderers
import Testing

/// A page's content-stream bytes are recovered on read: a scene written by `PDFRenderer` parses back to
/// a page whose content carries the operators that drew it. This is the `CGPDFPage` content a replay
/// interpreter consumes; here it is verified to round-trip intact.
struct PDFContentStreamTests {
    @Test func filledRectContentRoundTrips() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(Rect(x: 20, y: 30, width: 40, height: 25))

        let data = try PDFRenderer(width: 100, height: 100).render(context)
        let document = try #require(PDFDocumentReader().read([UInt8](data)))
        let page = try #require(document.pages.first)

        let content = page.contentText
        #expect(!page.content.isEmpty)
        // The flip from PDF's y-up space to PureDraw's y-down space, the fill colour, the rectangle as a
        // closed path, and the fill operator.
        #expect(content.contains("cm"))
        #expect(content.contains("1.0 0.0 0.0 rg")) // the red fill colour
        #expect(content.contains(" m\n")) // a moveto begins the path
        #expect(content.contains("h\n")) // the path is closed
        #expect(content.contains("\nf\n")) // the fill operator on its own line
    }

    @Test func contentIsEmptyForAPageWithoutAContentStream() throws {
        // A hand-written page with no /Contents has empty content, not a parse failure.
        let pdf = """
        %PDF-1.4
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [ 3 0 R ] /Count 1 >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R /MediaBox [ 0 0 100 100 ] >>
        endobj
        trailer
        << /Size 4 /Root 1 0 R >>
        startxref
        0
        %%EOF
        """
        let page = try #require(PDFDocumentReader().read([UInt8](pdf.utf8))?.pages.first)
        #expect(page.content.isEmpty)
    }

    @Test func contentStreamBytesAreRecoveredExactly() throws {
        // A hand-written page whose content stream is a known string is recovered byte-for-byte.
        let body = "0 0 100 100 re\nf\n"
        let pdf = """
        %PDF-1.4
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [ 3 0 R ] /Count 1 >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R /MediaBox [ 0 0 100 100 ] /Contents 4 0 R >>
        endobj
        4 0 obj
        << /Length \(body.utf8.count) >>
        stream
        \(body)
        endstream
        endobj
        trailer
        << /Size 5 /Root 1 0 R >>
        startxref
        0
        %%EOF
        """
        let page = try #require(PDFDocumentReader().read([UInt8](pdf.utf8))?.pages.first)
        #expect(page.contentText == body)
    }
}
