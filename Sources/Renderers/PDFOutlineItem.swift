//
//  PDFOutlineItem.swift
//  PureDraw
//

import Geometry

/// An entry in the document outline (the bookmarks sidebar). Children nest
/// to arbitrary depth; the destination is a point on the page in user space.
public struct PDFOutlineItem: Equatable, Sendable {
    /// The bookmark's displayed text.
    public let title: String
    /// The point on the page the bookmark jumps to, in user space.
    public let destination: Point
    /// Nested bookmarks under this one.
    public let children: [PDFOutlineItem]

    /// Creates an outline bookmark with a title, destination point, and optional nested items.
    public init(title: String, destination: Point, children: [PDFOutlineItem] = []) {
        self.title = title
        self.destination = destination
        self.children = children
    }
}
