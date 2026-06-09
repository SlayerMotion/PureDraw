//
//  FillRule.swift
//  PureDraw
//

/// Rules for determining the inside of a path during fill operations.
public enum FillRule: String, Sendable {
    case winding
    case evenOdd
}
