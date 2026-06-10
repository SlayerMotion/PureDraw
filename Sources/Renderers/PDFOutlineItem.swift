//
//  PDFOutlineItem.swift
//  PureDraw
//

import Geometry

/// An entry in the document outline (the bookmarks sidebar). Children nest
/// to arbitrary depth; the destination is a point on the page in user space.
public struct PDFOutlineItem: Equatable, Sendable {
    public let title: String
    public let destination: Point
    public let children: [PDFOutlineItem]

    public init(title: String, destination: Point, children: [PDFOutlineItem] = []) {
        self.title = title
        self.destination = destination
        self.children = children
    }
}
