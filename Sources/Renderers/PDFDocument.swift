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
        /// The page's content-stream bytes, the operators a `CGPDFPage` would draw. When the page's
        /// `/Contents` is an array of streams they are concatenated, separated by a newline, as the
        /// format requires. Empty when the page has no content stream.
        public let content: [UInt8]

        /// The content stream decoded as text, for inspection. Valid only for uncompressed streams.
        public var contentText: String {
            String(decoding: content, as: UTF8.self)
        }

        /// Creates a page from its boxes and optional content-stream bytes.
        public init(mediaBox: Rect, cropBox: Rect, content: [UInt8] = []) {
            self.mediaBox = mediaBox
            self.cropBox = cropBox
            self.content = content
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

        /// The transform that fits the box into `rect` for a top-left-origin (y-down) context, the form
        /// used to replay a page into a ``GraphicsContext``: like ``drawingTransform(for:in:)`` but with
        /// the y axis inverted, since a PDF page's space is bottom-left-origin (y-up). Seeding a
        /// ``PDFPageInterpreter`` with this cancels the content's own page-space flip, so the page is
        /// reproduced upright in the destination.
        public func destinationTransform(for box: PDFBox = .crop, into rect: Rect) -> AffineTransform {
            let source = boxRect(box)
            guard source.width > 0, source.height > 0, rect.width > 0, rect.height > 0 else { return .identity }
            let scale = min(rect.width / source.width, rect.height / source.height)
            let offsetX = rect.minX + (rect.width - source.width * scale) / 2
            let offsetY = rect.minY + (rect.height - source.height * scale) / 2
            // x' = offsetX + (x - minX) * scale; y' = offsetY + (height - (y - minY)) * scale (flipped).
            return AffineTransform(
                a: scale, b: 0, c: 0, d: -scale,
                tx: offsetX - source.minX * scale,
                ty: offsetY + source.height * scale + source.minY * scale
            )
        }
    }

    /// The pages in document order.
    public let pages: [Page]

    /// The number of pages, the `CGPDFDocumentGetNumberOfPages` equivalent.
    public var pageCount: Int {
        pages.count
    }
}
