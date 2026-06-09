//
//  BlendMode.swift
//  PureDraw
//

/// Blend modes for compositing shapes in the graphics context.
public enum BlendMode: String, Sendable, CaseIterable {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case difference
    case exclusion
}
