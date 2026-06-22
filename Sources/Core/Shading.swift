//
//  Shading.swift
//  PureDraw
//

import Geometry

/// A smooth colour field defined by a colour function over an axis or between two
/// circles, the `CGShading` equivalent (`CGShadingCreateAxial` /
/// `CGShadingCreateRadial` paired with a `CGFunction`). Draw it into the current
/// clip with ``GraphicsContext/drawShading(_:)``.
///
/// Quartz evaluates a shading by sampling its colour function as it rasterizes; this
/// type captures the function the same way, sampling it into a ``Gradient`` at
/// creation, so the value stays comparable and `Sendable` rather than holding an
/// opaque closure. A shading is therefore an axial or radial gradient whose stops
/// come from an arbitrary function rather than being supplied directly, plus the
/// `extendStart` / `extendEnd` flags that decide whether the end colours flood the
/// region beyond the axis or circles. Drawing lowers to the gradient machinery, so
/// every backend renders a shading exactly as it renders the equivalent gradient,
/// with no second rasterization path to keep in step.
public struct Shading: Equatable, Sendable {
    /// The geometry over which the colour function is evaluated.
    public enum Kind: Equatable, Sendable {
        /// Colour varying linearly along the axis from `start` to `end`.
        case axial(start: Point, end: Point)
        /// Colour varying between two circles, the `CGShadingCreateRadial` geometry.
        case radial(startCenter: Point, startRadius: Double, endCenter: Point, endRadius: Double)
    }

    /// The geometry the colour function is evaluated over.
    public let kind: Kind

    /// The colour function, sampled into stops over the parametric domain `[0, 1]`.
    public let gradient: Gradient

    /// Whether the start colour extends to fill the region before the axis or inner circle.
    public let extendStart: Bool

    /// Whether the end colour extends to fill the region after the axis or outer circle.
    public let extendEnd: Bool

    /// Creates an axial shading whose colour comes from `function`, evaluated over `[0, 1]` along the
    /// axis from `start` to `end`. The function is sampled `samples` times, as Quartz samples a
    /// `CGFunction` while rasterizing; raise `samples` for a sharper function.
    public init(
        axialFrom start: Point,
        to end: Point,
        extendStart: Bool = false,
        extendEnd: Bool = false,
        samples: Int = 256,
        function: (_ t: Double) -> Color
    ) {
        kind = .axial(start: start, end: end)
        gradient = Gradient(samples: samples, function)
        self.extendStart = extendStart
        self.extendEnd = extendEnd
    }

    /// Creates a radial shading whose colour comes from `function`, evaluated over `[0, 1]` from the
    /// start circle to the end circle.
    public init(
        radialFrom startCenter: Point,
        radius startRadius: Double,
        to endCenter: Point,
        radius endRadius: Double,
        extendStart: Bool = false,
        extendEnd: Bool = false,
        samples: Int = 256,
        function: (_ t: Double) -> Color
    ) {
        kind = .radial(startCenter: startCenter, startRadius: startRadius, endCenter: endCenter, endRadius: endRadius)
        gradient = Gradient(samples: samples, function)
        self.extendStart = extendStart
        self.extendEnd = extendEnd
    }

    /// Creates a shading directly from a prepared gradient and geometry, for callers that already hold
    /// sampled stops.
    public init(kind: Kind, gradient: Gradient, extendStart: Bool = false, extendEnd: Bool = false) {
        self.kind = kind
        self.gradient = gradient
        self.extendStart = extendStart
        self.extendEnd = extendEnd
    }

    /// The gradient drawing options that realise the extend flags.
    var drawingOptions: GradientDrawingOptions {
        var options: GradientDrawingOptions = []
        if extendStart { options.insert(.drawsBeforeStartLocation) }
        if extendEnd { options.insert(.drawsAfterEndLocation) }
        return options
    }
}
