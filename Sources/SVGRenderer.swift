//
//  SVGRenderer.swift
//  PureDraw
//

import Foundation

/// A renderer that exports a `GraphicsContext` drawing buffer as an SVG XML string.
public struct SVGRenderer: Renderer {
    public typealias Output = String

    /// The explicit width of the generated SVG. If nil, it is calculated from the bounds of the drawing.
    public let width: Double?

    /// The explicit height of the generated SVG. If nil, it is calculated from the bounds of the drawing.
    public let height: Double?

    public init(width: Double? = nil, height: Double? = nil) {
        self.width = width
        self.height = height
    }

    public func render(_ context: GraphicsContext) throws -> String {
        // 1. Gather all unique clip paths and shadows
        var uniqueClipPaths: [Path] = []
        var uniqueShadows: [Shadow] = []
        for op in context.commands {
            if let clip = op.state.clipPath {
                if !uniqueClipPaths.contains(clip) {
                    uniqueClipPaths.append(clip)
                }
            }
            if let shadow = op.state.shadow {
                if !uniqueShadows.contains(shadow) {
                    uniqueShadows.append(shadow)
                }
            }
        }

        // 2. Calculate the viewport / bounds
        let viewBoxMinX: Double
        let viewBoxMinY: Double
        let viewBoxWidth: Double
        let viewBoxHeight: Double

        if let w = width, let h = height {
            viewBoxMinX = 0.0
            viewBoxMinY = 0.0
            viewBoxWidth = w
            viewBoxHeight = h
        } else {
            var overallMinX = Double.infinity
            var overallMinY = Double.infinity
            var overallMaxX = -Double.infinity
            var overallMaxY = -Double.infinity

            for op in context.commands {
                let path: Path
                switch op.kind {
                case let .fill(p, _):
                    path = p
                case let .stroke(p):
                    path = p
                case .drawLinearGradient:
                    if let clip = op.state.clipPath {
                        path = clip
                    } else {
                        continue
                    }
                case .drawRadialGradient:
                    if let clip = op.state.clipPath {
                        path = clip
                    } else {
                        continue
                    }
                }

                let transformedPath = path.applying(op.state.transform)
                let bounds = transformedPath.boundingBox
                if bounds != .zero || !transformedPath.elements.isEmpty {
                    overallMinX = min(overallMinX, bounds.minX)
                    overallMinY = min(overallMinY, bounds.minY)
                    overallMaxX = max(overallMaxX, bounds.maxX)
                    overallMaxY = max(overallMaxY, bounds.maxY)
                }
            }

            viewBoxMinX = (overallMinX == .infinity) ? 0.0 : overallMinX
            viewBoxMinY = (overallMinY == .infinity) ? 0.0 : overallMinY
            let maxX = (overallMaxX == -.infinity) ? 100.0 : overallMaxX
            let maxY = (overallMaxY == -.infinity) ? 100.0 : overallMaxY
            viewBoxWidth = max(0.0, maxX - viewBoxMinX)
            viewBoxHeight = max(0.0, maxY - viewBoxMinY)
        }

        // 3. Serialize clip paths, shadows, and gradients into defs
        var defs: [String] = []
        for (index, clipPath) in uniqueClipPaths.enumerated() {
            let pathStr = svgPathString(for: clipPath)
            defs.append("    <clipPath id=\"clip-\(index)\">")
            defs.append("      <path d=\"\(pathStr)\" />")
            defs.append("    </clipPath>")
        }
        for (index, shadow) in uniqueShadows.enumerated() {
            let floodHex = hexColor(shadow.color)
            let floodAlpha = shadow.color.alpha
            defs.append("    <filter id=\"shadow-\(index)\">")
            defs
                .append(
                    "      <feDropShadow dx=\"\(shadow.offset.x)\" dy=\"\(shadow.offset.y)\" stdDeviation=\"\(shadow.blur / 2.0)\" flood-color=\"\(floodHex)\" flood-opacity=\"\(floodAlpha)\" />",
                )
            defs.append("    </filter>")
        }
        for (opIndex, op) in context.commands.enumerated() {
            switch op.kind {
            case let .drawLinearGradient(grad, start, end, _):
                defs
                    .append(
                        "    <linearGradient id=\"grad-\(opIndex)\" x1=\"\(start.x)\" y1=\"\(start.y)\" x2=\"\(end.x)\" y2=\"\(end.y)\" gradientUnits=\"userSpaceOnUse\" spreadMethod=\"pad\">",
                    )
                for stop in grad.stops {
                    let colorHex = hexColor(stop.color)
                    defs.append("      <stop offset=\"\(stop.location)\" stop-color=\"\(colorHex)\" stop-opacity=\"\(stop.color.alpha)\" />")
                }
                defs.append("    </linearGradient>")
            case let .drawRadialGradient(grad, startCenter, startRadius, endCenter, endRadius, _):
                defs
                    .append(
                        "    <radialGradient id=\"grad-\(opIndex)\" cx=\"\(endCenter.x)\" cy=\"\(endCenter.y)\" r=\"\(endRadius)\" fx=\"\(startCenter.x)\" fy=\"\(startCenter.y)\" fr=\"\(startRadius)\" gradientUnits=\"userSpaceOnUse\" spreadMethod=\"pad\">",
                    )
                for stop in grad.stops {
                    let colorHex = hexColor(stop.color)
                    defs.append("      <stop offset=\"\(stop.location)\" stop-color=\"\(colorHex)\" stop-opacity=\"\(stop.color.alpha)\" />")
                }
                defs.append("    </radialGradient>")
            default:
                break
            }
        }

        // 4. Render drawing operations
        var elements: [String] = []
        for (opIndex, op) in context.commands.enumerated() {
            switch op.kind {
            case let .fill(p, rule):
                let pathStr = svgPathString(for: p)
                let attrs = styleAttributes(for: op.state, hasFill: true, fillRule: rule, uniqueClipPaths: uniqueClipPaths, uniqueShadows: uniqueShadows)
                let attrsStr = attrs.joined(separator: " ")
                elements.append("  <path d=\"\(pathStr)\" \(attrsStr) />")
            case let .stroke(p):
                let pathStr = svgPathString(for: p)
                let attrs = styleAttributes(for: op.state, hasFill: false, fillRule: nil, uniqueClipPaths: uniqueClipPaths, uniqueShadows: uniqueShadows)
                let attrsStr = attrs.joined(separator: " ")
                elements.append("  <path d=\"\(pathStr)\" \(attrsStr) />")
            case .drawLinearGradient, .drawRadialGradient:
                if let clip = op.state.clipPath {
                    let pathStr = svgPathString(for: clip)
                    var attrs = styleAttributes(for: op.state, hasFill: false, fillRule: nil, uniqueClipPaths: uniqueClipPaths, uniqueShadows: uniqueShadows)
                    attrs.append("fill=\"url(#grad-\(opIndex))\"")
                    let attrsStr = attrs.joined(separator: " ")
                    elements.append("  <path d=\"\(pathStr)\" \(attrsStr) />")
                } else {
                    var attrs = styleAttributes(for: op.state, hasFill: false, fillRule: nil, uniqueClipPaths: uniqueClipPaths, uniqueShadows: uniqueShadows)
                    attrs.append("x=\"\(viewBoxMinX)\" y=\"\(viewBoxMinY)\" width=\"\(viewBoxWidth)\" height=\"\(viewBoxHeight)\"")
                    attrs.append("fill=\"url(#grad-\(opIndex))\"")
                    let attrsStr = attrs.joined(separator: " ")
                    elements.append("  <rect \(attrsStr) />")
                }
            }
        }

        // 5. Assemble final XML
        var svg: [String] = []
        let finalWidth = width ?? viewBoxWidth
        let finalHeight = height ?? viewBoxHeight

        svg
            .append(
                "<svg width=\"\(finalWidth)\" height=\"\(finalHeight)\" viewBox=\"\(viewBoxMinX) \(viewBoxMinY) \(viewBoxWidth) \(viewBoxHeight)\" xmlns=\"http://www.w3.org/2000/svg\">",
            )

        if !defs.isEmpty {
            svg.append("  <defs>")
            svg.append(contentsOf: defs)
            svg.append("  </defs>")
        }

        svg.append(contentsOf: elements)
        svg.append("</svg>")

        return svg.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func svgPathString(for path: Path) -> String {
        var d: [String] = []
        for element in path.elements {
            switch element {
            case let .move(to):
                d.append("M \(to.x) \(to.y)")
            case let .line(to):
                d.append("L \(to.x) \(to.y)")
            case let .quadCurve(to, control):
                d.append("Q \(control.x) \(control.y) \(to.x) \(to.y)")
            case let .cubicCurve(to, control1, control2):
                d.append("C \(control1.x) \(control1.y) \(control2.x) \(control2.y) \(to.x) \(to.y)")
            case .close:
                d.append("Z")
            }
        }
        return d.joined(separator: " ")
    }

    private func hexColor(_ color: Color) -> String {
        let r = Int(round(color.red * 255.0))
        let g = Int(round(color.green * 255.0))
        let b = Int(round(color.blue * 255.0))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func styleAttributes(
        for state: GraphicState,
        hasFill: Bool,
        fillRule: FillRule?,
        uniqueClipPaths: [Path],
        uniqueShadows: [Shadow],
    ) -> [String] {
        var attrs: [String] = []

        // Transform
        let t = state.transform
        if t != .identity {
            attrs.append("transform=\"matrix(\(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty))\"")
        }

        // Opacity
        if state.alpha != 1.0 {
            attrs.append("opacity=\"\(state.alpha)\"")
        }

        // Blend mode (using SVG style attribute)
        if state.blendMode != .normal {
            attrs.append("style=\"mix-blend-mode: \(state.blendMode.rawValue)\"")
        }

        // Fill
        if hasFill {
            let fill = state.fillColor
            if fill == .clear {
                attrs.append("fill=\"none\"")
            } else {
                attrs.append("fill=\"\(hexColor(fill))\"")
                if fill.alpha != 1.0 {
                    attrs.append("fill-opacity=\"\(fill.alpha)\"")
                }
            }
            if let rule = fillRule {
                let svgRule = (rule == .evenOdd) ? "evenodd" : "nonzero"
                attrs.append("fill-rule=\"\(svgRule)\"")
            }
        } else {
            attrs.append("fill=\"none\"")
        }

        // Stroke
        if !hasFill {
            let stroke = state.strokeColor
            if stroke == .clear {
                attrs.append("stroke=\"none\"")
            } else {
                attrs.append("stroke=\"\(hexColor(stroke))\"")
                if stroke.alpha != 1.0 {
                    attrs.append("stroke-opacity=\"\(stroke.alpha)\"")
                }
            }
            attrs.append("stroke-width=\"\(state.lineWidth)\"")
            attrs.append("stroke-linecap=\"\(state.lineCap.rawValue)\"")
            attrs.append("stroke-linejoin=\"\(state.lineJoin.rawValue)\"")
            if state.lineJoin == .miter {
                attrs.append("stroke-miterlimit=\"\(state.miterLimit)\"")
            }
            if !state.dashPattern.isEmpty {
                let dashStr = state.dashPattern.map { String($0) }.joined(separator: ",")
                attrs.append("stroke-dasharray=\"\(dashStr)\"")
                if state.dashPhase != 0.0 {
                    attrs.append("stroke-dashoffset=\"\(state.dashPhase)\"")
                }
            }
        }

        // Clipping
        if let clip = state.clipPath, let clipIndex = uniqueClipPaths.firstIndex(of: clip) {
            attrs.append("clip-path=\"url(#clip-\(clipIndex))\"")
        }

        // Shadow
        if let shadow = state.shadow, let shadowIndex = uniqueShadows.firstIndex(of: shadow) {
            attrs.append("filter=\"url(#shadow-\(shadowIndex))\"")
        }

        return attrs
    }
}
