//
//  PostScriptRenderer.swift
//  PureDraw
//

import Foundation

/// A renderer that exports a `GraphicsContext` drawing buffer as a PostScript Level 3 (EPS) XML/Text string.
public struct PostScriptRenderer: Renderer {
    public typealias Output = String

    /// The explicit width of the generated EPS. If nil, calculated from content bounds.
    public let width: Double?

    /// The explicit height of the generated EPS. If nil, calculated from content bounds.
    public let height: Double?

    public init(width: Double? = nil, height: Double? = nil) {
        self.width = width
        self.height = height
    }

    public func render(_ context: GraphicsContext) throws -> String {
        // 1. Calculate Bounding Box
        let minX: Double
        let minY: Double
        let maxX: Double
        let maxY: Double

        if let w = width, let h = height {
            minX = 0.0
            minY = 0.0
            maxX = w
            maxY = h
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

            minX = (overallMinX == .infinity) ? 0.0 : overallMinX
            minY = (overallMinY == .infinity) ? 0.0 : overallMinY
            maxX = (overallMaxX == -.infinity) ? 100.0 : overallMaxX
            maxY = (overallMaxY == -.infinity) ? 100.0 : overallMaxY
        }

        let viewBoxHeight = max(0.0, maxY - minY)

        // Assemble EPS header
        var ps = ""
        ps += "%!PS-Adobe-3.0 EPSF-3.0\n"
        ps += "%%BoundingBox: \(Int(floor(minX))) \(Int(floor(minY))) \(Int(ceil(maxX))) \(Int(ceil(maxY)))\n"
        ps += "%%EndComments\n\n"

        // Map Y-axis from top-left (PureDraw) to bottom-left (PostScript)
        ps += "1 -1 scale 0 -\(viewBoxHeight) translate\n\n"

        for op in context.commands {
            ps += "gsave\n"

            // 1. Transform
            let t = op.state.transform
            if t != .identity {
                ps += "[ \(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty) ] concat\n"
            }

            // 2. Line properties
            ps += "\(op.state.lineWidth) setlinewidth\n"

            let capValue = switch op.state.lineCap {
            case .butt: 0
            case .round: 1
            case .square: 2
            }
            ps += "\(capValue) setlinecap\n"

            let joinValue = switch op.state.lineJoin {
            case .miter: 0
            case .round: 1
            case .bevel: 2
            }
            ps += "\(joinValue) setlinejoin\n"
            ps += "\(op.state.miterLimit) setmiterlimit\n"

            if !op.state.dashPattern.isEmpty {
                let patternStr = op.state.dashPattern.map { String($0) }.joined(separator: " ")
                ps += "[\(patternStr)] \(op.state.dashPhase) setdash\n"
            } else {
                ps += "[] 0 setdash\n"
            }

            // 3. Clip Path
            if let clip = op.state.clipPath {
                ps += psPathString(for: clip)
                ps += "clip newpath\n"
            }

            // 3b. Draw Shadow (if present)
            if let shadow = op.state.shadow {
                ps += "gsave\n"
                ps += "\(shadow.offset.x) \(shadow.offset.y) translate\n"
                ps += "\(shadow.color.red) \(shadow.color.green) \(shadow.color.blue) setrgbcolor\n"
                switch op.kind {
                case let .fill(path, rule):
                    ps += psPathString(for: path)
                    if rule == .evenOdd {
                        ps += "eofill\n"
                    } else {
                        ps += "fill\n"
                    }
                case let .stroke(path):
                    ps += psPathString(for: path)
                    ps += "stroke\n"
                default:
                    if let clip = op.state.clipPath {
                        ps += psPathString(for: clip)
                        ps += "fill\n"
                    }
                }
                ps += "grestore\n"
            }

            // 4. Draw
            switch op.kind {
            case let .fill(path, rule):
                ps += "\(op.state.fillColor.red) \(op.state.fillColor.green) \(op.state.fillColor.blue) setrgbcolor\n"
                ps += psPathString(for: path)
                if rule == .evenOdd {
                    ps += "eofill\n"
                } else {
                    ps += "fill\n"
                }
            case let .stroke(path):
                ps += "\(op.state.strokeColor.red) \(op.state.strokeColor.green) \(op.state.strokeColor.blue) setrgbcolor\n"
                ps += psPathString(for: path)
                ps += "stroke\n"
            case let .drawLinearGradient(grad, start, end, options):
                let extendStart = options.contains(.drawsBeforeStartLocation)
                let extendEnd = options.contains(.drawsAfterEndLocation)
                ps += """
                <<
                  /ShadingType 2
                  /ColorSpace /DeviceRGB
                  /Coords [ \(start.x) \(start.y) \(end.x) \(end.y) ]
                  /Function \(psFunction(for: grad))
                  /Extend [ \(extendStart) \(extendEnd) ]
                >> shfill

                """
            case let .drawRadialGradient(grad, startCenter, startRadius, endCenter, endRadius, options):
                let extendStart = options.contains(.drawsBeforeStartLocation)
                let extendEnd = options.contains(.drawsAfterEndLocation)
                ps += """
                <<
                  /ShadingType 3
                  /ColorSpace /DeviceRGB
                  /Coords [ \(startCenter.x) \(startCenter.y) \(startRadius) \(endCenter.x) \(endCenter.y) \(endRadius) ]
                  /Function \(psFunction(for: grad))
                  /Extend [ \(extendStart) \(extendEnd) ]
                >> shfill

                """
            }

            ps += "grestore\n"
        }

        return ps
    }

    private func psPathString(for path: Path) -> String {
        var str = ""
        var currentPoint = Point(x: 0, y: 0)

        for element in path.elements {
            switch element {
            case let .move(to):
                str += "\(to.x) \(to.y) moveto\n"
                currentPoint = to
            case let .line(to):
                str += "\(to.x) \(to.y) lineto\n"
                currentPoint = to
            case let .quadCurve(to, control):
                let c1x = currentPoint.x + (2.0 / 3.0) * (control.x - currentPoint.x)
                let c1y = currentPoint.y + (2.0 / 3.0) * (control.y - currentPoint.y)
                let c2x = to.x + (2.0 / 3.0) * (control.x - to.x)
                let c2y = to.y + (2.0 / 3.0) * (control.y - to.y)
                str += "\(c1x) \(c1y) \(c2x) \(c2y) \(to.x) \(to.y) curveto\n"
                currentPoint = to
            case let .cubicCurve(to, control1, control2):
                str += "\(control1.x) \(control1.y) \(control2.x) \(control2.y) \(to.x) \(to.y) curveto\n"
                currentPoint = to
            case .close:
                str += "closepath\n"
            }
        }
        return str
    }

    private func psFunction(for gradient: Gradient) -> String {
        let stops = gradient.stops.sorted(by: { $0.location < $1.location })
        if stops.count < 2 {
            return "<< /FunctionType 2 /Domain [ 0 1 ] /C0 [ 0 0 0 ] /C1 [ 0 0 0 ] /N 1 >>"
        }
        if stops.count == 2 {
            let s0 = stops[0]
            let s1 = stops[1]
            return "<< /FunctionType 2 /Domain [ 0 1 ] /C0 [ \(s0.color.red) \(s0.color.green) \(s0.color.blue) ] /C1 [ \(s1.color.red) \(s1.color.green) \(s1.color.blue) ] /N 1 >>"
        }

        var bounds: [String] = []
        var encode: [String] = []
        var functions: [String] = []

        for i in 0 ..< (stops.count - 1) {
            let s0 = stops[i]
            let s1 = stops[i + 1]
            if i > 0 {
                bounds.append("\(s0.location)")
            }
            encode.append("0 1")
            functions
                .append(
                    "<< /FunctionType 2 /Domain [ 0 1 ] /C0 [ \(s0.color.red) \(s0.color.green) \(s0.color.blue) ] /C1 [ \(s1.color.red) \(s1.color.green) \(s1.color.blue) ] /N 1 >>",
                )
        }

        return """
        <<
          /FunctionType 3
          /Domain [ 0 1 ]
          /Functions [
            \(functions.joined(separator: "\n    "))
          ]
          /Bounds [ \(bounds.joined(separator: " ")) ]
          /Encode [ \(encode.joined(separator: " ")) ]
        >>
        """
    }
}
