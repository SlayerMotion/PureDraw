//
//  Layer.swift
//  PureDraw
//

import Geometry

/// A cached drawing layer for repeated stamp/brush drawing, the `CGLayer`
/// equivalent. Record into `context`, then stamp with
/// `GraphicsContext.draw(_:in:)` or `draw(_:at:)`.
///
/// Backends with a native cache (`BitmapRenderer`, `CoreGraphicsRenderer`)
/// render the layer once per pass and reuse the result for every stamp;
/// vector backends inline the layer's commands per stamp via
/// `GraphicsContext.flattenedCommands`.
///
/// Layers compare by identity, like `CGLayer`. Finish recording before
/// rendering; the class is not synchronized for concurrent mutation.
public final class Layer: @unchecked Sendable, Equatable {
    /// The layer's width in points.
    public let width: Double
    /// The layer's height in points.
    public let height: Double
    /// The layer's own drawing surface; record commands into it.
    public var context: GraphicsContext

    /// Creates an empty layer of the given size with its own graphics context.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
        context = GraphicsContext()
    }

    /// Layers have reference identity; two layers are equal only when they are the same instance.
    public static func == (lhs: Layer, rhs: Layer) -> Bool {
        lhs === rhs
    }
}

public extension GraphicsContext {
    /// The recorded commands with every `drawLayer` operation expanded into
    /// the layer's commands, transformed into the destination's space.
    /// Backends without a native layer cache render these instead of
    /// `commands`. Nesting is capped at eight levels; deeper (or cyclic)
    /// layer references are dropped.
    var flattenedCommands: [DrawOperation] {
        Self.flattenLayers(Self.lowerText(commands), depth: 8)
    }

    /// The recorded commands with layers expanded, preserving `showText`
    /// operations that carry a source string so backends that emit native
    /// text (SVG, PDF) can render them. Glyph-index runs (no source string)
    /// and text nested in a stamped layer are lowered to outlines.
    var layerFlattenedCommands: [DrawOperation] {
        Self.flattenLayers(Self.lowerText(commands, preservingNamedText: true), depth: 8)
    }

    /// The recorded commands with `showText` operations lowered to glyph
    /// outline fills/strokes, leaving layers intact. Pixel backends render
    /// this so text becomes vector paths.
    var textLoweredCommands: [DrawOperation] {
        Self.lowerText(commands)
    }

    static func lowerText(_ operations: [DrawOperation], preservingNamedText: Bool = false) -> [DrawOperation] {
        var result: [DrawOperation] = []
        for operation in operations {
            guard case let .showText(glyphs, text, font, fontSize, drawingMode, textMatrix, position) = operation.kind else {
                result.append(operation)
                continue
            }
            // A run with a source string and an identity text matrix can be
            // rendered as native text by SVG/PDF; leave it intact for them.
            // Anything else lowers to outlines so it stays correct.
            if preservingNamedText, text != nil, textMatrix == .identity {
                result.append(operation)
                continue
            }
            guard font.unitsPerEm > 0, drawingMode != .invisible else { continue }
            let scale = fontSize / Double(font.unitsPerEm)
            var pen = position
            for glyph in glyphs {
                if let outline = font.outline(forGlyph: glyph) {
                    // Font units are y-up; user space is y-down, so flip while
                    // scaling, then apply the text matrix and the pen position.
                    let placement = AffineTransform.identity
                        .scaledBy(x: scale, y: -scale)
                        .concatenating(textMatrix)
                        .translatedBy(x: pen.x, y: pen.y)
                    let placed = outline.applying(placement)
                    switch drawingMode {
                    case .fill:
                        result.append(DrawOperation(kind: .fill(placed, rule: .winding), state: operation.state))
                    case .stroke:
                        result.append(DrawOperation(kind: .stroke(placed), state: operation.state))
                    case .fillStroke:
                        result.append(DrawOperation(kind: .fill(placed, rule: .winding), state: operation.state))
                        result.append(DrawOperation(kind: .stroke(placed), state: operation.state))
                    case .invisible:
                        break
                    }
                }
                let advance = font.advanceWidth(forGlyph: glyph) * scale + operation.state.characterSpacing
                pen = Point(x: pen.x + advance * textMatrix.a, y: pen.y + advance * textMatrix.b)
            }
        }
        return result
    }

    private static func flattenLayers(_ operations: [DrawOperation], depth: Int) -> [DrawOperation] {
        var result: [DrawOperation] = []
        for operation in operations {
            guard case let .drawLayer(layer, rect) = operation.kind else {
                result.append(operation)
                continue
            }
            guard depth > 0, layer.width > 0, layer.height > 0 else { continue }

            let placement = AffineTransform.identity
                .scaledBy(x: rect.width / layer.width, y: rect.height / layer.height)
                .translatedBy(x: rect.minX, y: rect.minY)

            // Text nested in a stamped layer lowers to outlines so the layer
            // placement transform applies correctly.
            for subOperation in flattenLayers(lowerText(layer.context.commands), depth: depth - 1) {
                var state = subOperation.state
                state.transform = subOperation.state.transform
                    .concatenating(placement)
                    .concatenating(operation.state.transform)
                state.alpha *= operation.state.alpha
                if state.clipPath == nil, let outerClip = operation.state.clipPath {
                    // The outer clip lives in the outer op's user space; bring
                    // it into the sub-op's user space so renderers map it back
                    // to the same device-space shape.
                    state.clipPath = outerClip
                        .applying(operation.state.transform)
                        .applying(state.transform.inverted())
                }
                if state.maskImage == nil {
                    state.maskImage = operation.state.maskImage
                    state.maskRect = operation.state.maskRect
                    state.maskTransform = operation.state.maskTransform
                }
                if state.blendMode == .normal {
                    state.blendMode = operation.state.blendMode
                }
                result.append(DrawOperation(kind: subOperation.kind, state: state))
            }
        }
        return result
    }
}
