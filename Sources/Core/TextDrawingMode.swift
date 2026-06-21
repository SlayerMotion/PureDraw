//
//  TextDrawingMode.swift
//  PureDraw
//

/// How shown text is painted, the `CGTextDrawingMode` equivalent.
/// `invisible` advances the text position without painting, for measuring.
/// The clip variants paint (or, for `clip`, do not) and then intersect the glyph
/// outlines into the clipping path, so subsequent drawing is painted through the
/// letters, mirroring `kCGTextFillClip` / `kCGTextStrokeClip` / `kCGTextClip`.
public enum TextDrawingMode: String, Equatable, Sendable, Codable, CaseIterable {
    case fill
    case stroke
    case fillStroke
    case invisible
    case fillClip
    case strokeClip
    case fillStrokeClip
    case clip

    /// Whether this mode adds the glyph outlines to the clipping path.
    public var clips: Bool {
        switch self {
        case .fillClip, .strokeClip, .fillStrokeClip, .clip: true
        case .fill, .stroke, .fillStroke, .invisible: false
        }
    }

    /// The painting performed before any clip is applied: the equivalent
    /// non-clipping mode (`clip` paints nothing, like `invisible`).
    public var paintMode: TextDrawingMode {
        switch self {
        case .fill, .fillClip: .fill
        case .stroke, .strokeClip: .stroke
        case .fillStroke, .fillStrokeClip: .fillStroke
        case .invisible, .clip: .invisible
        }
    }
}
