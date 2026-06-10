//
//  CanvasRenderer.swift
//  PureDraw
//

import Core
import Foundation
import Geometry

/// A renderer that translates a `GraphicsContext` drawing buffer into HTML5 Canvas 2D Context JavaScript code.
public struct CanvasRenderer: Renderer {
    public typealias Output = String

    /// The name of the HTML5 Canvas 2D context variable in the generated JavaScript code (default: "ctx").
    public let contextName: String

    public init(contextName: String = "ctx") {
        self.contextName = contextName
    }

    public func draw(_ context: GraphicsContext) throws -> String {
        var js: [String] = []

        // Wrap in save/restore to keep global context clean
        js.append("\(contextName).save();")

        for (opIndex, op) in context.flattenedCommands.enumerated() {
            js.append("")
            js.append("// Operation \(opIndex)")

            switch op.kind {
            case .beginTransparencyLayer:
                js.append("\(contextName).save();")
                let t = op.state.transform
                if t != .identity {
                    js.append("\(contextName).transform(\(t.a), \(t.b), \(t.c), \(t.d), \(t.tx), \(t.ty));")
                }
                if op.state.alpha != 1.0 {
                    js.append("\(contextName).globalAlpha = \(op.state.alpha);")
                }
                if op.state.blendMode != .normal {
                    js.append("\(contextName).globalCompositeOperation = '\(canvasBlendMode(op.state.blendMode))';")
                }
                if let shadow = op.state.shadow {
                    js.append("\(contextName).shadowOffsetX = \(shadow.offset.x);")
                    js.append("\(contextName).shadowOffsetY = \(shadow.offset.y);")
                    js.append("\(contextName).shadowBlur = \(shadow.blur);")
                    js.append("\(contextName).shadowColor = '\(rgbaColor(shadow.color))';")
                }
                if let clip = op.state.clipPath {
                    js.append("\(contextName).beginPath();")
                    appendPathElements(clip, to: &js)
                    js.append("\(contextName).clip();")
                }
            case .endTransparencyLayer:
                js.append("\(contextName).restore();")
            default:
                js.append("\(contextName).save();")

                // 1. Apply CTM
                let t = op.state.transform
                if t != .identity {
                    js.append("\(contextName).transform(\(t.a), \(t.b), \(t.c), \(t.d), \(t.tx), \(t.ty));")
                }

                // 2. Alpha & Blend Mode
                if op.state.alpha != 1.0 {
                    js.append("\(contextName).globalAlpha = \(op.state.alpha);")
                }
                if op.state.blendMode != .normal {
                    js.append("\(contextName).globalCompositeOperation = '\(canvasBlendMode(op.state.blendMode))';")
                }

                // 3. Stroke Styles
                js.append("\(contextName).lineWidth = \(op.state.lineWidth);")
                js.append("\(contextName).lineCap = '\(op.state.lineCap.rawValue)';")
                js.append("\(contextName).lineJoin = '\(op.state.lineJoin.rawValue)';")
                js.append("\(contextName).miterLimit = \(op.state.miterLimit);")

                if !op.state.dashPattern.isEmpty {
                    let patternStr = op.state.dashPattern.map { String($0) }.joined(separator: ", ")
                    js.append("\(contextName).setLineDash([\(patternStr)]);")
                    js.append("\(contextName).lineDashOffset = \(op.state.dashPhase);")
                }

                // 4. Shadow Styles
                if let shadow = op.state.shadow {
                    js.append("\(contextName).shadowOffsetX = \(shadow.offset.x);")
                    js.append("\(contextName).shadowOffsetY = \(shadow.offset.y);")
                    js.append("\(contextName).shadowBlur = \(shadow.blur);")
                    js.append("\(contextName).shadowColor = '\(rgbaColor(shadow.color))';")
                }

                // 5. Clip Path
                if let clip = op.state.clipPath {
                    js.append("\(contextName).beginPath();")
                    appendPathElements(clip, to: &js)
                    js.append("\(contextName).clip();")
                }

                // 6. Draw Operation
                switch op.kind {
                case let .fill(path, rule):
                    js.append("\(contextName).fillStyle = '\(rgbaColor(op.state.fillColor))';")
                    js.append("\(contextName).beginPath();")
                    appendPathElements(path, to: &js)
                    let canvasRule = rule == .evenOdd ? "'evenodd'" : "'nonzero'"
                    js.append("\(contextName).fill(\(canvasRule));")

                case let .stroke(path):
                    js.append("\(contextName).strokeStyle = '\(rgbaColor(op.state.strokeColor))';")
                    js.append("\(contextName).beginPath();")
                    appendPathElements(path, to: &js)
                    js.append("\(contextName).stroke();")

                case let .drawLinearGradient(grad, start, end, _):
                    let gradVarName = "linearGrad_\(opIndex)"
                    js.append("const \(gradVarName) = \(contextName).createLinearGradient(\(start.x), \(start.y), \(end.x), \(end.y));")
                    for stop in grad.stops {
                        js.append("\(gradVarName).addColorStop(\(stop.location), '\(rgbaColor(stop.color))');")
                    }
                    js.append("\(contextName).fillStyle = \(gradVarName);")
                    fillContextArea(using: op.state.clipPath, to: &js)

                case let .drawRadialGradient(grad, startCenter, startRadius, endCenter, endRadius, _):
                    let gradVarName = "radialGrad_\(opIndex)"
                    js
                        .append(
                            "const \(gradVarName) = \(contextName).createRadialGradient(\(startCenter.x), \(startCenter.y), \(startRadius), \(endCenter.x), \(endCenter.y), \(endRadius));"
                        )
                    for stop in grad.stops {
                        js.append("\(gradVarName).addColorStop(\(stop.location), '\(rgbaColor(stop.color))');")
                    }
                    js.append("\(contextName).fillStyle = \(gradVarName);")
                    fillContextArea(using: op.state.clipPath, to: &js)

                case .beginTransparencyLayer, .endTransparencyLayer:
                    break

                case .drawLayer:
                    break // expanded by flattenedCommands

                case let .drawImage(image, rect):
                    let canvasVar = "imgCanvas_\(opIndex)"
                    let ctxVar = "imgCtx_\(opIndex)"
                    let dataVar = "imgData_\(opIndex)"
                    js.append("const \(canvasVar) = document.createElement('canvas');")
                    js.append("\(canvasVar).width = \(image.width);")
                    js.append("\(canvasVar).height = \(image.height);")
                    js.append("const \(ctxVar) = \(canvasVar).getContext('2d');")
                    js.append("const \(dataVar) = \(ctxVar).createImageData(\(image.width), \(image.height));")
                    js.append("\(dataVar).data.set([\(canvasImageDataArray(for: image))]);")
                    js.append("\(ctxVar).putImageData(\(dataVar), 0, 0);")
                    js.append("\(contextName).drawImage(\(canvasVar), \(rect.origin.x), \(rect.origin.y), \(rect.width), \(rect.height));")
                }

                js.append("\(contextName).restore();")
            }
        }

        js.append("\(contextName).restore();")
        return js.joined(separator: "\n")
    }

    /// Helper to output a complete, previewable HTML file containing a `<canvas>` element and the drawing JS.
    public func renderToHTMLPage(_ context: GraphicsContext, width: Double, height: Double, canvasID: String = "pureDrawCanvas") throws -> String {
        let drawingJS = try render(context)
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>PureDraw Canvas Preview</title>
            <style>
                body {
                    margin: 0;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    background-color: #f0f0f5;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                }
                .canvas-container {
                    background-color: #ffffff;
                    border-radius: 12px;
                    box-shadow: 0 8px 30px rgba(0, 0, 0, 0.12);
                    padding: 16px;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                }
                canvas {
                    border: 1px solid #e0e0e0;
                    border-radius: 6px;
                }
                h1 {
                    font-size: 1.2rem;
                    color: #333;
                    margin: 0 0 12px 0;
                }
            </style>
        </head>
        <body>
            <div class="canvas-container">
                <h1>PureDraw HTML5 Canvas Preview</h1>
                <canvas id="\(canvasID)" width="\(width)" height="\(height)"></canvas>
            </div>
            <script>
                (function() {
                    const canvas = document.getElementById('\(canvasID)');
                    if (!canvas) return;
                    const \(contextName) = canvas.getContext('2d');
                    if (!\(contextName)) return;

                    \(drawingJS)
                })();
            </script>
        </body>
        </html>
        """
    }

    private func appendPathElements(_ path: Path, to js: inout [String]) {
        for element in path.elements {
            switch element {
            case let .move(to):
                js.append("\(contextName).moveTo(\(to.x), \(to.y));")
            case let .line(to):
                js.append("\(contextName).lineTo(\(to.x), \(to.y));")
            case let .quadCurve(to, control):
                js.append("\(contextName).quadraticCurveTo(\(control.x), \(control.y), \(to.x), \(to.y));")
            case let .cubicCurve(to, cp1, cp2):
                js.append("\(contextName).bezierCurveTo(\(cp1.x), \(cp1.y), \(cp2.x), \(cp2.y), \(to.x), \(to.y));")
            case .close:
                js.append("\(contextName).closePath();")
            }
        }
    }

    private func fillContextArea(using clipPath: Path?, to js: inout [String]) {
        // If there's a clip path, we fill its bounding box.
        // If there is no clip path, we fill a sufficiently large viewport area.
        if let clip = clipPath {
            let bounds = clip.boundingBox
            js.append("\(contextName).fillRect(\(bounds.minX), \(bounds.minY), \(bounds.width), \(bounds.height));")
        } else {
            js.append("\(contextName).fillRect(-10000, -10000, 20000, 20000);")
        }
    }

    private func rgbaColor(_ color: Color) -> String {
        let r = Int((color.red * 255.0).rounded())
        let g = Int((color.green * 255.0).rounded())
        let b = Int((color.blue * 255.0).rounded())
        return "rgba(\(r), \(g), \(b), \(color.alpha))"
    }

    private func canvasBlendMode(_ mode: BlendMode) -> String {
        switch mode {
        case .normal: "source-over"
        case .plusLighter: "lighter"
        case .plusDarker: "darker"
        default: mode.rawValue
        }
    }

    private func canvasImageDataArray(for image: Image) -> String {
        var values: [String] = []
        let pixelCount = image.width * image.height
        values.reserveCapacity(pixelCount * 4)

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

            values.append(String(Int(round(outR * 255.0))))
            values.append(String(Int(round(outG * 255.0))))
            values.append(String(Int(round(outB * 255.0))))
            values.append(String(Int(round(outA * 255.0))))
        }

        return values.joined(separator: ",")
    }
}
