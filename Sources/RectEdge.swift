//
//  RectEdge.swift
//  PureDraw
//

/// Represents an edge of a rectangle, used primarily for layout division operations.
public enum RectEdge: String, Sendable, CaseIterable {
    case minX
    case minY
    case maxX
    case maxY
}
