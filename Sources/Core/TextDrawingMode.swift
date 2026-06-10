//
//  TextDrawingMode.swift
//  PureDraw
//

/// How shown text is painted, the `CGTextDrawingMode` equivalent.
/// `invisible` advances the text position without painting, for measuring.
public enum TextDrawingMode: String, Equatable, Sendable, Codable, CaseIterable {
    case fill
    case stroke
    case fillStroke
    case invisible
}
