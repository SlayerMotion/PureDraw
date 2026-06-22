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

        /// Creates a page from its media and crop boxes.
        public init(mediaBox: Rect, cropBox: Rect) {
            self.mediaBox = mediaBox
            self.cropBox = cropBox
        }

        /// The rectangle for a named box, defaulting to the media box when absent, as `CGPDFPageGetBoxRect` does.
        public func boxRect(_ box: PDFBox) -> Rect {
            switch box {
            case .media: mediaBox
            case .crop: cropBox
            case .bleed, .trim, .art: mediaBox
            }
        }

        /// The transform that fits the given box into `rect`, the `CGPDFPageGetDrawingTransform`
        /// equivalent for an unrotated page: scale the box uniformly to fit (preserving its aspect
        /// ratio), then center it in `rect`. Drawing a page through this transform places it inside the
        /// destination without distortion. Page rotation (`/Rotate`) is not yet applied.
        public func drawingTransform(for box: PDFBox = .crop, in rect: Rect) -> AffineTransform {
            let source = boxRect(box)
            guard source.width > 0, source.height > 0, rect.width > 0, rect.height > 0 else { return .identity }
            let scale = min(rect.width / source.width, rect.height / source.height)
            let scaledWidth = source.width * scale
            let scaledHeight = source.height * scale
            // Map the box's lower-left to the centered position, then scale: x' = scale*(x - minX) + offset.
            let tx = rect.minX + (rect.width - scaledWidth) / 2 - source.minX * scale
            let ty = rect.minY + (rect.height - scaledHeight) / 2 - source.minY * scale
            return AffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)
        }
    }

    /// The pages in document order.
    public let pages: [Page]

    /// The number of pages, the `CGPDFDocumentGetNumberOfPages` equivalent.
    public var pageCount: Int {
        pages.count
    }
}
