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
                case let .drawImage(_, rect):
                    var p = Path()
                    p.move(to: Point(x: rect.minX, y: rect.minY))
                    p.addLine(to: Point(x: rect.maxX, y: rect.minY))
                    p.addLine(to: Point(x: rect.maxX, y: rect.maxY))
                    p.addLine(to: Point(x: rect.minX, y: rect.maxY))
                    p.closeSubpath()
                    path = p
                case .beginTransparencyLayer, .endTransparencyLayer:
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
                    "      <feDropShadow dx=\"\(shadow.offset.x)\" dy=\"\(shadow.offset.y)\" stdDeviation=\"\(shadow.blur / 2.0)\" flood-color=\"\(floodHex)\" flood-opacity=\"\(floodAlpha)\" />"
                )
            defs.append("    </filter>")
        }
        for (opIndex, op) in context.commands.enumerated() {
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
        for index in stride(from: 0, to: image.data.count, by: 4) {
            guard index + 3 < image.data.count else { break }
            let r = Double(image.data[index]) / 255.0
            let g = Double(image.data[index + 1]) / 255.0
            let b = Double(image.data[index + 2]) / 255.0
            let a = Double(image.data[index + 3]) / 255.0

            var outR = r
            var outG = g
            var outB = b
            var outA = a

            switch image.alphaInfo {
            case .premultipliedLast, .premultipliedFirst:
                if a > 0 {
                    outR = r / a
                    outG = g / a
                    outB = b / a
                }
            case .last, .first:
                break
            case .none, .noneSkipLast, .noneSkipFirst:
                outA = 1.0
            }

            let byteB = UInt8(min(255, max(0, Int(round(outB * 255.0)))))
            let byteG = UInt8(min(255, max(0, Int(round(outG * 255.0)))))
            let byteR = UInt8(min(255, max(0, Int(round(outR * 255.0)))))
            let byteA = UInt8(min(255, max(0, Int(round(outA * 255.0)))))

            data.append(contentsOf: [byteB, byteG, byteR, byteA])
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
