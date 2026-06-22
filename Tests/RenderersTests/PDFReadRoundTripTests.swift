//
//  PDFReadRoundTripTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
import Renderers
import Testing

/// The read side of PDF: a document written by `PDFRenderer` is parsed back by `PDFDocumentReader`
/// into a page model. The round trip asserts page count and the media box; a hand-written minimal PDF
/// checks the parser does not depend on the writer's exact bytes, and box inheritance is exercised.
struct PDFReadRoundTripTests {
    @Test func writtenPDFRoundTripsToItsPageModel() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(Rect(x: 10, y: 10, width: 80, height: 60))

        let data = try PDFRenderer(width: 120, height: 90).render(context)
        let document = try #require(PDFDocumentReader().read([UInt8](data)))

        #expect(document.pageCount == 1)
        let page = try #require(document.pages.first)
        #expect(page.mediaBox == Rect(x: 0, y: 0, width: 120, height: 90))
        // An absent crop box defaults to the media box, as CGPDFPageGetBoxRect returns.
        #expect(page.boxRect(.crop) == page.mediaBox)
        #expect(page.boxRect(.art) == page.mediaBox)
    }

    @Test func parsesAHandWrittenMinimalPDF() throws {
        // A minimal three-object PDF: catalog, pages, one page with a media box.
        let pdf = """
        %PDF-1.4
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [ 3 0 R ] /Count 1 >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R /MediaBox [ 0 0 200 300 ] >>
        endobj
        trailer
        << /Size 4 /Root 1 0 R >>
        startxref
        0
        %%EOF
        """
        let document = try #require(PDFDocumentReader().read([UInt8](pdf.utf8)))
        #expect(document.pageCount == 1)
        #expect(document.pages.first?.mediaBox == Rect(x: 0, y: 0, width: 200, height: 300))
    }

    @Test func mediaBoxIsInheritedFromThePagesNode() throws {
        // The page omits its own MediaBox; it must inherit the one on the Pages node.
        let pdf = """
        %PDF-1.4
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [ 3 0 R ] /Count 1 /MediaBox [ 0 0 400 500 ] >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R >>
        endobj
        trailer
        << /Size 4 /Root 1 0 R >>
        startxref
        0
        %%EOF
        """
        let document = try #require(PDFDocumentReader().read([UInt8](pdf.utf8)))
        #expect(document.pages.first?.mediaBox == Rect(x: 0, y: 0, width: 400, height: 500))
    }

    @Test func multiPageTreeCollectsEveryLeaf() throws {
        let pdf = """
        %PDF-1.4
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [ 3 0 R 4 0 R ] /Count 2 /MediaBox [ 0 0 100 100 ] >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R >>
        endobj
        4 0 obj
        << /Type /Page /Parent 2 0 R /MediaBox [ 0 0 50 75 ] >>
        endobj
        trailer
        << /Size 5 /Root 1 0 R >>
        startxref
        0
        %%EOF
        """
        let document = try #require(PDFDocumentReader().read([UInt8](pdf.utf8)))
        #expect(document.pageCount == 2)
        #expect(document.pages[0].mediaBox == Rect(x: 0, y: 0, width: 100, height: 100))
        #expect(document.pages[1].mediaBox == Rect(x: 0, y: 0, width: 50, height: 75))
    }
}
