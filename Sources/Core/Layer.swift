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
    public let width: Double
    public let height: Double
    /// The layer's own drawing surface; record commands into it.
    public var context: GraphicsContext

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
        context = GraphicsContext()
    }

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
        Self.flattenLayers(commands, depth: 8)
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

            for subOperation in flattenLayers(layer.context.commands, depth: depth - 1) {
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
