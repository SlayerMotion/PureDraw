//
//  PDFLink.swift
//  PureDraw
//

import Geometry

/// A hot-spot link annotation on the page: a URI or an internal jump to a
/// point on the page. The rect is in user space (top-left origin) and is
/// converted to PDF coordinates on write.
public struct PDFLink: Equatable, Sendable {
    /// Where the link leads: an external URI, or an internal jump to a point on the page.
    public enum Target: Equatable, Sendable {
        case url(String)
        case destination(Point)
    }

    /// The clickable area in user space (top-left origin).
    public let rect: Rect
    /// Where the link leads.
    public let target: Target

    /// Creates a link annotation over `rect` that leads to `target`.
    public init(rect: Rect, target: Target) {
        self.rect = rect
        self.target = target
    }
}
