//
//  PDFDocument.swift
//  PureDraw
//

import Geometry

/// A parsed PDF document's page model, the read side of `CGPDFDocument`. This is the structural layer:
/// page count and box rects. Replaying a page's content stream is a separate concern.
public struct PDFDocument: Equatable, Sendable {
    /// One page's geometry.
    public struct Page: Equatable, Sendable {
        /// The media box, the page's full coordinate rectangle.
        public let mediaBox: Rect
        /// The crop box; defaults to the media box when the page does not set one.
        public let cropBox: Rect

        /// The rectangle for a named box, defaulting to the media box when absent, as `CGPDFPageGetBoxRect` does.
        public func boxRect(_ box: PDFBox) -> Rect {
            switch box {
            case .media: mediaBox
            case .crop: cropBox
            case .bleed, .trim, .art: mediaBox
            }
        }
    }

    /// The pages in document order.
    public let pages: [Page]

    /// The number of pages, the `CGPDFDocumentGetNumberOfPages` equivalent.
    public var pageCount: Int {
        pages.count
    }
}
