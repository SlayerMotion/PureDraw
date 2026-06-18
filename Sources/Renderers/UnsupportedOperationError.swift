//
//  UnsupportedOperationError.swift
//  PureDraw
//

/// Thrown by a vector renderer (SVG, PostScript, Canvas, PDF) when a draw operation it
/// cannot represent reaches it, so the operation's content is NOT silently dropped.
///
/// The vector renderers translate the command buffer into a target format. Some operations
/// have no faithful equivalent in a given format (a projective image warp, an explicit
/// drop-shadow), and were previously skipped with no signal to the caller, silently losing
/// part of the drawing. They now fail loud: flatten or rasterize the unsupported operation
/// first (e.g. render through `BitmapRenderer`), or omit it before exporting.
public struct UnsupportedOperationError: Error, Equatable, CustomStringConvertible {
    /// The unsupported draw operation, e.g. `"drawImageProjective"`.
    public let operation: String
    /// The renderer that cannot represent it, e.g. `"SVGRenderer"`.
    public let renderer: String

    public init(operation: String, renderer: String) {
        self.operation = operation
        self.renderer = renderer
    }

    public var description: String {
        "\(renderer) cannot represent the \(operation) operation; rasterize or flatten it before exporting rather than dropping it silently."
    }
}
