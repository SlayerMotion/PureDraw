//
//  Pattern.swift
//  PureDraw
//

import Geometry
import Validation

/// A tiling cell painted repeatedly to fill a region, the `CGPattern`
/// equivalent. Record the cell into `context`; the cell repeats every
/// `xStep`/`yStep` units in pattern space.
///
/// A *colored* pattern carries its own colors. An *uncolored* (stencil)
/// pattern ignores the cell's colors and paints with the fill color in
/// effect when the pattern is used, like `CGPatternCreate` with an uncolored
/// color space.
///
/// Patterns compare by identity, like `CGPattern`. Finish recording the cell
/// before filling; the class is not synchronized for concurrent mutation.
public final class Pattern: @unchecked Sendable, Equatable {
    /// The cell's extent in pattern space.
    public let bounds: Rect
    /// Horizontal tiling step; defaults to the cell width.
    public let xStep: Double
    /// Vertical tiling step; defaults to the cell height.
    public let yStep: Double
    /// Whether the cell carries its own colors (`true`) or is a stencil
    /// painted with the current fill color (`false`).
    public let isColored: Bool
    /// The cell's drawing surface; record commands into it.
    public var context: GraphicsContext

    public init(bounds: Rect, xStep: Double? = nil, yStep: Double? = nil, isColored: Bool = true) {
        self.bounds = bounds
        self.xStep = xStep ?? bounds.width
        self.yStep = yStep ?? bounds.height
        self.isColored = isColored
        context = GraphicsContext()
    }

    public static func == (lhs: Pattern, rhs: Pattern) -> Bool {
        lhs === rhs
    }
}

extension Pattern: Validatable {
    public static var defaultValidator: Validator<Pattern> {
        Validator().validating(.patternIsValid)
    }
}

extension GraphicsContext {
    /// Total tile cap, a backstop against a tiny step over a huge fill.
    private static let maxPatternTiles = 20000

    /// Expands a pattern fill into per-tile cell operations, each clipped to
    /// the filled path. Tiling happens in the current user space; the cell's
    /// own commands carry through their transforms, colors (colored patterns)
    /// or the current fill color (uncolored patterns), composed with the
    /// current CTM.
    func patternFillCommands(of path: Path, pattern: Pattern) -> [DrawOperation] {
        guard pattern.bounds.width > 0, pattern.bounds.height > 0,
              pattern.xStep > 0, pattern.yStep > 0
        else { return [] }

        let bbox = path.boundingBox
        guard !bbox.isNull, !bbox.isEmpty else { return [] }

        // Tile indices whose cell extent intersects the fill bounding box.
        let iMin = Int(((bbox.minX - pattern.bounds.minX - pattern.bounds.width) / pattern.xStep).rounded(.down))
        let iMax = Int(((bbox.maxX - pattern.bounds.minX) / pattern.xStep).rounded(.up))
        let jMin = Int(((bbox.minY - pattern.bounds.minY - pattern.bounds.height) / pattern.yStep).rounded(.down))
        let jMax = Int(((bbox.maxY - pattern.bounds.minY) / pattern.yStep).rounded(.up))
        guard iMin <= iMax, jMin <= jMax else { return [] }
        guard (iMax - iMin + 1) * (jMax - jMin + 1) <= Self.maxPatternTiles else { return [] }

        let cellCommands = pattern.context.flattenedCommands
        guard !cellCommands.isEmpty else { return [] }

        var result: [DrawOperation] = []

        let ctm = currentState.transform
        let fillColor = currentState.fillColor
        let outerClip = currentState.clipPath
        let baseAlpha = currentState.alpha

        for j in jMin ... jMax {
            for i in iMin ... iMax {
                let tile = AffineTransform.translation(x: Double(i) * pattern.xStep, y: Double(j) * pattern.yStep)
                for cellOp in cellCommands {
                    let composed = cellOp.state.transform
                        .concatenating(tile)
                        .concatenating(ctm)

                    var state = cellOp.state
                    state.transform = composed
                    state.alpha *= baseAlpha

                    // Bring the fill path (and any outer clip) into the
                    // sub-op's local space so renderers map them to the same
                    // device-space region.
                    let inverse = composed.inverted()
                    var clip = path.applying(ctm).applying(inverse)
                    if let outerClip {
                        clip.addPath(outerClip.applying(ctm).applying(inverse))
                    }
                    state.clipPath = clip

                    if !pattern.isColored {
                        state.fillColor = fillColor
                        state.strokeColor = fillColor
                    }
                    result.append(DrawOperation(kind: cellOp.kind, state: state))
                }
            }
        }
        return result
    }
}
