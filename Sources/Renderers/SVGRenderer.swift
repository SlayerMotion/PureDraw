//
//  SVGRenderer.swift
//  PureDraw
//

import Core
import Foundation
import Geometry

/// A renderer that exports a `GraphicsContext` drawing buffer as an SVG XML string.
public struct SVGRenderer: Renderer {
    public typealias Output = String

    /// The explicit width of the generated SVG. If nil, it is calculated from the bounds of the drawing.
    public let width: Double?

    /// The explicit height of the generated SVG. If nil, it is calculated from the bounds of the drawing.
    public let height: Double?

    /// Creates an SVG renderer; an explicit width and height set the document's viewport, and a nil
    /// value lets it derive from the drawing's bounds.
    public init(width: Double? = nil, height: Double? = nil) {
        self.width = width
        self.height = height
    }

    /// Emits an SVG document reproducing the context's recorded operations.
    public func draw(_ context: GraphicsContext) throws -> String {
        // 1. Gather all unique clip paths and shadows
        var uniqueClipPaths: [[Path]] = [] // each entry is a clip STACK, intersected
        var uniqueShadows: [Shadow] = []
        for op in context.flattenedCommands {
            if !op.state.clipPaths.isEmpty, !uniqueClipPaths.contains(op.state.clipPaths) {
                uniqueClipPaths.append(op.state.clipPaths)
            }
            // An explicit drop shadow realizes its shadow through its own shadow-only filter, so it
            // must not contribute a source-plus-shadow feDropShadow filter to the implicit-shadow set.
            if case .dropShadow = op.kind { continue }
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

            for op in context.flattenedCommands {
                let path: Path
                switch op.kind {
                case let .fill(p, _):
                    path = p
                case let .stroke(p):
                    path = p
                case .drawLinearGradient, .drawRadialGradient, .drawConicGradient:
                    if let clip = op.state.clipPath {
                        path = clip
                    } else {
                        continue
                    }
                case let .drawImage(_, rect):
                    var p = Path()
                    p.move(to: Point(x: rect.minX, y: rect.minY))
                    p.addLine(to: Point(x: rect.maxX, y: rect.minY))
                    p.addLine(to: Point(x: rect.maxX, y: rect.maxY))
                    p.addLine(to: Point(x: rect.minX, y: rect.maxY))
                    p.closeSubpath()
                    path = p
                case .beginTransparencyLayer, .endTransparencyLayer, .drawLayer, .drawImageProjective, .dropShadow, .showText:
                    continue
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

            // isFinite (not == ±infinity) so NaN and the opposite infinity also fall back,
            // keeping the emitted viewBox/width/height finite instead of "nan"/"inf".
            viewBoxMinX = overallMinX.isFinite ? overallMinX : 0.0
            viewBoxMinY = overallMinY.isFinite ? overallMinY : 0.0
            let maxX = overallMaxX.isFinite ? overallMaxX : 100.0
            let maxY = overallMaxY.isFinite ? overallMaxY : 100.0
            viewBoxWidth = max(0.0, maxX - viewBoxMinX)
            viewBoxHeight = max(0.0, maxY - viewBoxMinY)
        }

        // 3. Serialize clip paths, shadows, and gradients into defs
        var defs: [String] = []
        // Each clip is the INTERSECTION of its stack. SVG <clipPath> children union, so
        // intersection is expressed by NESTING: each path's clipPath references the
        // previous one via clip-path; the element references the final id "clip-N". A
        // single-clip stack emits one "clip-N" with no nesting (unchanged output).
        for (index, stack) in uniqueClipPaths.enumerated() {
            for (depth, clipPath) in stack.enumerated() {
                let id = depth == stack.count - 1 ? "clip-\(index)" : "clip-\(index)-\(depth)"
                let inner = depth == 0 ? "" : " clip-path=\"url(#clip-\(index)-\(depth - 1))\""
                defs.append("    <clipPath id=\"\(id)\">")
                defs.append("      <path d=\"\(svgPathString(for: clipPath))\"\(inner) />")
                defs.append("    </clipPath>")
            }
        }
        for (index, shadow) in uniqueShadows.enumerated() {
            let floodHex = hexColor(shadow.color)
            let floodAlpha = shadow.color.alpha
            defs.append("    <filter id=\"shadow-\(index)\">")
            defs
                .append(
                    "      <feDropShadow dx=\"\(shadow.offset.x)\" dy=\"\(shadow.offset.y)\" stdDeviation=\"\(shadow.blur / 2.0)\" flood-color=\"\(floodHex)\" flood-opacity=\"\(floodAlpha)\" />"
                )
            defs.append("    </filter>")
        }
        for (opIndex, op) in context.layerFlattenedCommands.enumerated() {
            switch op.kind {
            case let .drawLinearGradient(grad, start, end, _):
                defs
                    .append(
                        "    <linearGradient id=\"grad-\(opIndex)\" x1=\"\(start.x)\" y1=\"\(start.y)\" x2=\"\(end.x)\" y2=\"\(end.y)\" gradientUnits=\"userSpaceOnUse\" spreadMethod=\"pad\">"
                    )
                for stop in grad.stops {
                    let colorHex = hexColor(stop.color)
                    defs.append("      <stop offset=\"\(stop.location)\" stop-color=\"\(colorHex)\" stop-opacity=\"\(stop.color.alpha)\" />")
                }
                defs.append("    </linearGradient>")
            case let .drawRadialGradient(grad, startCenter, startRadius, endCenter, endRadius, _):
                defs
                    .append(
                        "    <radialGradient id=\"grad-\(opIndex)\" cx=\"\(endCenter.x)\" cy=\"\(endCenter.y)\" r=\"\(endRadius)\" fx=\"\(startCenter.x)\" fy=\"\(startCenter.y)\" fr=\"\(startRadius)\" gradientUnits=\"userSpaceOnUse\" spreadMethod=\"pad\">"
                    )
                for stop in grad.stops {
                    let colorHex = hexColor(stop.color)
                    defs.append("      <stop offset=\"\(stop.location)\" stop-color=\"\(colorHex)\" stop-opacity=\"\(stop.color.alpha)\" />")
                }
                defs.append("    </radialGradient>")
            case .dropShadow:
                // The explicit drop shadow paints only the shadow of a path (the CALayer.shadowPath
                // analog), so it needs a shadow-only filter rather than the source-plus-shadow
                // feDropShadow used for an implicit state shadow: blur the path's alpha, offset it,
                // and flood it with the shadow colour clipped to that offset alpha.
                if let shadow = op.state.shadow {
                    let floodHex = hexColor(shadow.color)
                    defs.append("    <filter id=\"dropshadow-\(opIndex)\" x=\"-50%\" y=\"-50%\" width=\"200%\" height=\"200%\">")
                    defs.append("      <feGaussianBlur in=\"SourceAlpha\" stdDeviation=\"\(shadow.blur / 2.0)\" />")
                    defs.append("      <feOffset dx=\"\(shadow.offset.x)\" dy=\"\(shadow.offset.y)\" result=\"offsetblur\" />")
                    defs.append("      <feFlood flood-color=\"\(floodHex)\" flood-opacity=\"\(shadow.color.alpha)\" />")
                    defs.append("      <feComposite in2=\"offsetblur\" operator=\"in\" />")
                    defs.append("    </filter>")
                }
            default:
                break
            }
        }

        // 4. Render drawing operations
        var elements: [String] = []
        for (opIndex, op) in context.layerFlattenedCommands.enumerated() {
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
            case .drawConicGradient:
                // SVG has no broadly-supported conic/angular gradient; fail loud rather than
                // drop it. The raster (BitmapRenderer) and Canvas paths render it.
                throw UnsupportedOperationError(operation: "drawConicGradient", renderer: "SVGRenderer")
            case let .drawImage(image, rect):
                let bmpData = createBMPData(from: image)
                let base64String = bmpData.base64EncodedString()
                var attrs = styleAttributes(for: op.state, hasFill: false, fillRule: nil, uniqueClipPaths: uniqueClipPaths, uniqueShadows: uniqueShadows)
                attrs.append("x=\"\(rect.origin.x)\" y=\"\(rect.origin.y)\" width=\"\(rect.width)\" height=\"\(rect.height)\"")
                attrs.append("href=\"data:image/bmp;base64,\(base64String)\"")
                let attrsStr = attrs.joined(separator: " ")
                elements.append("  <image \(attrsStr) />")
            case .beginTransparencyLayer:
                let attrs = styleAttributes(for: op.state, hasFill: false, fillRule: nil, uniqueClipPaths: uniqueClipPaths, uniqueShadows: uniqueShadows)
                let attrsStr = attrs.joined(separator: " ")
                elements.append("  <g \(attrsStr)>")
            case .endTransparencyLayer:
                elements.append("  </g>")
            case let .showText(_, text, _, fontSize, drawingMode, textMatrix, position, _):
                if let element = svgTextElement(
                    text: text,
                    fontSize: fontSize,
                    drawingMode: drawingMode,
                    textMatrix: textMatrix,
                    position: position,
                    state: op.state,
                    uniqueClipPaths: uniqueClipPaths,
                    uniqueShadows: uniqueShadows
                ) {
                    elements.append(element)
                }
            case .drawLayer:
                break // expanded by layerFlattenedCommands
            case .drawImageProjective:
                // A projective (perspective) image map is not expressible in SVG: <image> and the
                // transform attribute apply only an affine matrix, and there is no standard element
                // for a perspective texture map. Fail loud rather than silently degrade to affine.
                throw UnsupportedOperationError(operation: "drawImageProjective", renderer: "SVGRenderer")
            case let .dropShadow(p):
                // Paint only the shadow of the path through the shadow-only filter built in defs.
                // With no shadow set the operation paints nothing, matching the raster renderer.
                guard op.state.shadow != nil else { break }
                let pathStr = svgPathString(for: p)
                var attrs: [String] = []
                let t = op.state.transform
                if t != .identity {
                    attrs.append("transform=\"matrix(\(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty))\"")
                }
                if !op.state.clipPaths.isEmpty, let clipIndex = uniqueClipPaths.firstIndex(of: op.state.clipPaths) {
                    attrs.append("clip-path=\"url(#clip-\(clipIndex))\"")
                }
                // The fill is irrelevant: the filter rebuilds the output from SourceAlpha and feFlood.
                attrs.append("fill=\"black\"")
                attrs.append("filter=\"url(#dropshadow-\(opIndex))\"")
                elements.append("  <path d=\"\(pathStr)\" \(attrs.joined(separator: " ")) />")
            }
        }

        // 5. Assemble final XML
        var svg: [String] = []
        let finalWidth = width ?? viewBoxWidth
        let finalHeight = height ?? viewBoxHeight

        svg
            .append(
                "<svg width=\"\(finalWidth)\" height=\"\(finalHeight)\" viewBox=\"\(viewBoxMinX) \(viewBoxMinY) \(viewBoxWidth) \(viewBoxHeight)\" xmlns=\"http://www.w3.org/2000/svg\">"
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

    /// Builds an SVG `<text>` element for a named text run. The element carries
    /// the CTM via `styleAttributes`, so the baseline position is expressed in
    /// user space. The run's text matrix is always identity here (other runs
    /// lower to outlines), so font-size handles scaling and the baseline
    /// handles the y axis. The glyph shapes depend on the viewer's font
    /// substitution; the text is real and selectable.
    private func svgTextElement(
        text: String?,
        fontSize: Double,
        drawingMode: TextDrawingMode,
        textMatrix _: Geometry.AffineTransform,
        position: Point,
        state: GraphicState,
        uniqueClipPaths: [[Path]],
        uniqueShadows: [Shadow]
    ) -> String? {
        guard let text, drawingMode != .invisible, !text.isEmpty else { return nil }
        var attrs = styleAttributes(
            for: state,
            hasFill: drawingMode != .stroke,
            fillRule: nil,
            uniqueClipPaths: uniqueClipPaths,
            uniqueShadows: uniqueShadows
        )
        attrs.append("x=\"\(position.x)\" y=\"\(position.y)\"")
        attrs.append("font-size=\"\(fontSize)\"")
        if state.characterSpacing != 0 {
            attrs.append("letter-spacing=\"\(state.characterSpacing)\"")
        }
        return "  <text \(attrs.joined(separator: " "))>\(escapeXML(text))</text>"
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The path printer is the canonical normal form owned by `SVGPathData`, so
    /// the SVG renderer and the SVG path importer share one description and cannot
    /// drift. See `Core/SVGPathData.swift`.
    private func svgPathString(for path: Path) -> String {
        path.svgPathData
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
        uniqueClipPaths: [[Path]],
        uniqueShadows: [Shadow]
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
        if state.blendMode != .normal, state.blendMode.isCSSBlendMode {
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

        // Clipping (reference the final id of this clip stack's nested clipPaths).
        if !state.clipPaths.isEmpty, let clipIndex = uniqueClipPaths.firstIndex(of: state.clipPaths) {
            attrs.append("clip-path=\"url(#clip-\(clipIndex))\"")
        }

        // Shadow
        if let shadow = state.shadow, let shadowIndex = uniqueShadows.firstIndex(of: shadow) {
            attrs.append("filter=\"url(#shadow-\(shadowIndex))\"")
        }

        return attrs
    }

    private func createBMPData(from image: Image) -> Data {
        let width = image.width
        let height = image.height

        let headerSize = 108 // BITMAPV4HEADER
        let fileHeaderSize = 14
        let totalHeaderSize = fileHeaderSize + headerSize
        let pixelDataSize = width * height * 4
        let fileSize = totalHeaderSize + pixelDataSize

        var data = Data(capacity: fileSize)

        // --- FILE HEADER (14 bytes) ---
        data.append(contentsOf: [0x42, 0x4D]) // bfType: "BM"
        appendUInt32(UInt32(fileSize), to: &data) // bfSize
        appendUInt16(0, to: &data) // bfReserved1
        appendUInt16(0, to: &data) // bfReserved2
        appendUInt32(UInt32(totalHeaderSize), to: &data) // bfOffBits

        // --- BITMAPV4HEADER (108 bytes) ---
        appendUInt32(UInt32(headerSize), to: &data) // bV4Size
        appendInt32(Int32(width), to: &data) // bV4Width
        appendInt32(-Int32(height), to: &data) // bV4Height (negative for top-down)
        appendUInt16(1, to: &data) // bV4Planes
        appendUInt16(32, to: &data) // bV4BitCount
        appendUInt32(3, to: &data) // bV4V4Compression (BI_BITFIELDS)
        appendUInt32(UInt32(pixelDataSize), to: &data) // bV4SizeImage
        appendInt32(2835, to: &data) // bV4XPelsPerMeter
        appendInt32(2835, to: &data) // bV4YPelsPerMeter
        appendUInt32(0, to: &data) // bV4ClrUsed
        appendUInt32(0, to: &data) // bV4ClrImportant

        // Color masks (Red, Green, Blue, Alpha)
        appendUInt32(0x00FF_0000, to: &data) // bV4RedMask
        appendUInt32(0x0000_FF00, to: &data) // bV4GreenMask
        appendUInt32(0x0000_00FF, to: &data) // bV4BlueMask
        appendUInt32(0xFF00_0000, to: &data) // bV4AlphaMask

        // bV4CSType: "sRGB" (0x73524742)
        appendUInt32(0x7352_4742, to: &data)

        // bV4Endpoints: 36 bytes of 0
        data.append(contentsOf: Array(repeating: UInt8(0), count: 36))

        // Gamma Red, Green, Blue
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(0, to: &data)

        // --- PIXEL DATA ---
        // Resolve each pixel through `pixelColor`, which already decodes the bit depth, un-premultiplies
        // alpha, and looks up an indexed palette. This makes wide (16-bit/float), decode-array, and
        // indexed images export correctly, and skips any row padding rather than treating it as pixels.
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let color = image.pixelColor(x: x, y: y)
                let byteB = UInt8(min(255, max(0, Int(round(color.blue * 255.0)))))
                let byteG = UInt8(min(255, max(0, Int(round(color.green * 255.0)))))
                let byteR = UInt8(min(255, max(0, Int(round(color.red * 255.0)))))
                let byteA = UInt8(min(255, max(0, Int(round(color.alpha * 255.0)))))
                data.append(contentsOf: [byteB, byteG, byteR, byteA])
            }
        }

        return data
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private func appendInt32(_ value: Int32, to data: inout Data) {
        appendUInt32(UInt32(bitPattern: value), to: &data)
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }
}
