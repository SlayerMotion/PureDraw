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

    public let rect: Rect
    public let target: Target

    public init(rect: Rect, target: Target) {
        self.rect = rect
        self.target = target
    }
}
