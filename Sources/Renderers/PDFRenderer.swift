//
//  PDFRenderer.swift
//  PureDraw
//

import Core
import Foundation
import Geometry

/// A renderer that exports a `GraphicsContext` drawing buffer as a PDF document (binary Data).
public struct PDFRenderer: Renderer {
    public typealias Output = Data

    public let width: Double
    public let height: Double

    public init(width: Double = 500, height: Double = 500) {
        self.width = width
        self.height = height
    }

    public func render(_ context: GraphicsContext) throws -> Data {
        let writer = PDFWriter()

        var extGStates: [ExtGStateKey: String] = [:]
        var shadings: [String: String] = [:] // shading dictionary content -> name

        var contentStream = ""

        // PDF coordinate system starts at bottom-left.
        // PureDraw/CoreGraphics coordinate system starts at top-left.
        // We concatenate a transform to flip the Y axis.
        contentStream += "1 0 0 -1 0 \(height) cm\n"

        for op in context.commands {
            contentStream += "q\n"

            // 1. Transform
            let t = op.state.transform
            if t != .identity {
                contentStream += "\(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty) cm\n"
            }

            // 2. Alpha and Blend Mode
            let fillAlpha = op.state.fillColor.alpha * op.state.alpha
            let strokeAlpha = op.state.strokeColor.alpha * op.state.alpha
            let blendMode = op.state.blendMode
            if fillAlpha < 1.0 || strokeAlpha < 1.0 || blendMode != .normal {
                let key = ExtGStateKey(ca: fillAlpha, CA: strokeAlpha, blendMode: blendMode)
                let gsName: String
                if let existing = extGStates[key] {
                    gsName = existing
                } else {
                    gsName = "GS\(extGStates.count + 1)"
                    extGStates[key] = gsName
                }
                contentStream += "/\(gsName) gs\n"
            }

            // 3. Line properties
            contentStream += "\(op.state.lineWidth) w\n"

            let capValue = switch op.state.lineCap {
            case .butt: 0
            case .round: 1
            case .square: 2
            }
            contentStream += "\(capValue) J\n"

            let joinValue = switch op.state.lineJoin {
            case .miter: 0
            case .round: 1
            case .bevel: 2
            }
            contentStream += "\(joinValue) j\n"
            contentStream += "\(op.state.miterLimit) M\n"
            contentStream += "\(op.state.flatness) i\n"

            if !op.state.dashPattern.isEmpty {
                let patternStr = op.state.dashPattern.map { String($0) }.joined(separator: " ")
                contentStream += "[\(patternStr)] \(op.state.dashPhase) d\n"
            } else {
                contentStream += "[] 0 d\n"
            }

            // 4. Clip Path
            if let clip = op.state.clipPath {
                let pathStr = pdfPathString(for: clip)
                contentStream += pathStr
                contentStream += "W n\n"
            }

            // 4b. Draw Shadow (if present)
            if let shadow = op.state.shadow {
                contentStream += "q\n"
                contentStream += "1 0 0 1 \(shadow.offset.x) \(shadow.offset.y) cm\n"

                let shadowAlpha = shadow.color.alpha * op.state.alpha
                let shadowKey = ExtGStateKey(ca: shadowAlpha, CA: shadowAlpha, blendMode: .normal)
                let sgsName: String
                if let existing = extGStates[shadowKey] {
                    sgsName = existing
                } else {
                    sgsName = "GS\(extGStates.count + 1)"
                    extGStates[shadowKey] = sgsName
                }
                contentStream += "/\(sgsName) gs\n"
                contentStream += "\(shadow.color.red) \(shadow.color.green) \(shadow.color.blue) rg\n"

                switch op.kind {
                case let .fill(path, rule):
                    let pathStr = pdfPathString(for: path)
                    contentStream += pathStr
                    if rule == .evenOdd {
                        contentStream += "f*\n"
                    } else {
                        contentStream += "f\n"
                    }
                case let .stroke(path):
                    contentStream += "\(shadow.color.red) \(shadow.color.green) \(shadow.color.blue) RG\n"
                    let pathStr = pdfPathString(for: path)
                    contentStream += pathStr
                    contentStream += "S\n"
                case .drawLinearGradient, .drawRadialGradient:
                    if let clip = op.state.clipPath {
                        let pathStr = pdfPathString(for: clip)
                        contentStream += pathStr
                        contentStream += "f\n"
                    }
                }
                contentStream += "Q\n"
            }

            // 5. Draw
            switch op.kind {
            case let .fill(path, rule):
                contentStream += "\(op.state.fillColor.red) \(op.state.fillColor.green) \(op.state.fillColor.blue) rg\n"
                let pathStr = pdfPathString(for: path)
                contentStream += pathStr
                if rule == .evenOdd {
                    contentStream += "f*\n"
                } else {
                    contentStream += "f\n"
                }
            case let .stroke(path):
                contentStream += "\(op.state.strokeColor.red) \(op.state.strokeColor.green) \(op.state.strokeColor.blue) RG\n"
                let pathStr = pdfPathString(for: path)
                contentStream += pathStr
                contentStream += "S\n"
            case let .drawLinearGradient(grad, start, end, options):
                let extendStart = options.contains(.drawsBeforeStartLocation)
                let extendEnd = options.contains(.drawsAfterEndLocation)
                let shadingDict = """
                <<
                  /ShadingType 2
                  /ColorSpace /DeviceRGB
                  /Coords [ \(start.x) \(start.y) \(end.x) \(end.y) ]
                  /Function \(pdfFunction(for: grad))
                  /Extend [ \(extendStart) \(extendEnd) ]
                >>
                """
                let shName: String
                if let existing = shadings[shadingDict] {
                    shName = existing
                } else {
                    shName = "Sh\(shadings.count + 1)"
                    shadings[shadingDict] = shName
                }
                contentStream += "/\(shName) sh\n"
            case let .drawRadialGradient(grad, startCenter, startRadius, endCenter, endRadius, options):
                let extendStart = options.contains(.drawsBeforeStartLocation)
                let extendEnd = options.contains(.drawsAfterEndLocation)
                let shadingDict = """
                <<
                  /ShadingType 3
                  /ColorSpace /DeviceRGB
                  /Coords [ \(startCenter.x) \(startCenter.y) \(startRadius) \(endCenter.x) \(endCenter.y) \(endRadius) ]
                  /Function \(pdfFunction(for: grad))
                  /Extend [ \(extendStart) \(extendEnd) ]
                >>
                """
                let shName: String
                if let existing = shadings[shadingDict] {
                    shName = existing
                } else {
                    shName = "Sh\(shadings.count + 1)"
                    shadings[shadingDict] = shName
                }
                contentStream += "/\(shName) sh\n"
            }

            contentStream += "Q\n"
        }

        // Assemble resources and document catalog objects
        _ = writer.append("<< /Type /Catalog /Pages 2 0 R >>")
        _ = writer.append("<< /Type /Pages /Kids [ 3 0 R ] /Count 1 >>")

        var resourcesStr = "<<"
        if !extGStates.isEmpty {
            resourcesStr += "\n  /ExtGState <<"
            for (key, gsName) in extGStates {
                let bmName = switch key.blendMode {
                case .normal: "Normal"
                case .multiply: "Multiply"
                case .screen: "Screen"
                case .overlay: "Overlay"
                case .darken: "Darken"
                case .lighten: "Lighten"
                case .colorDodge: "ColorDodge"
                case .colorBurn: "ColorBurn"
                case .softLight: "SoftLight"
                case .hardLight: "HardLight"
                case .difference: "Difference"
                case .exclusion: "Exclusion"
                case .hue: "Hue"
                case .saturation: "Saturation"
                case .color: "Color"
                case .luminosity: "Luminosity"
                default: "Normal"
                }
                resourcesStr += "\n    /\(gsName) << /Type /ExtGState /ca \(key.ca) /CA \(key.CA) /BM /\(bmName) >>"
            }
            resourcesStr += "\n  >>"
        }
        if !shadings.isEmpty {
            resourcesStr += "\n  /Shading <<"
            for (key, shName) in shadings {
                resourcesStr += "\n    /\(shName) \(key)"
            }
            resourcesStr += "\n  >>"
        }
        resourcesStr += "\n>>"

        _ = writer.append("<< /Type /Page /Parent 2 0 R /MediaBox [ 0 0 \(width) \(height) ] /Contents 4 0 R /Resources \(resourcesStr) >>")
        _ = writer.append("<< /Length \(contentStream.data(using: .utf8)?.count ?? 0) >>\nstream\n\(contentStream)\nendstream")

        return writer.buildData()
    }

    private func pdfPathString(for path: Path) -> String {
        var str = ""
        var currentPoint = Point(x: 0, y: 0)

        for element in path.elements {
            switch element {
            case let .move(to):
                str += "\(to.x) \(to.y) m\n"
                currentPoint = to
            case let .line(to):
                str += "\(to.x) \(to.y) l\n"
                currentPoint = to
            case let .quadCurve(to, control):
                let c1x = currentPoint.x + (2.0 / 3.0) * (control.x - currentPoint.x)
                let c1y = currentPoint.y + (2.0 / 3.0) * (control.y - currentPoint.y)
                let c2x = to.x + (2.0 / 3.0) * (control.x - to.x)
                let c2y = to.y + (2.0 / 3.0) * (control.y - to.y)
                str += "\(c1x) \(c1y) \(c2x) \(c2y) \(to.x) \(to.y) c\n"
                currentPoint = to
            case let .cubicCurve(to, control1, control2):
                str += "\(control1.x) \(control1.y) \(control2.x) \(control2.y) \(to.x) \(to.y) c\n"
                currentPoint = to
            case .close:
                str += "h\n"
            }
        }
        return str
    }

    private func pdfFunction(for gradient: Gradient) -> String {
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
                    "<< /FunctionType 2 /Domain [ 0 1 ] /C0 [ \(s0.color.red) \(s0.color.green) \(s0.color.blue) ] /C1 [ \(s1.color.red) \(s1.color.green) \(s1.color.blue) ] /N 1 >>"
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

    // MARK: - Nested Helper Types

    private struct ExtGStateKey: Hashable {
        let ca: Double
        let CA: Double
        let blendMode: BlendMode
    }

    private class PDFWriter {
        var objects: [String] = []

        func append(_ objectContent: String) -> Int {
            let objIndex = objects.count + 1
            let fullObject = "\(objIndex) 0 obj\n\(objectContent)\nendobj\n"
            objects.append(fullObject)
            return objIndex
        }

        func buildData() -> Data {
            var data = Data()

            let header = "%PDF-1.4\n"
            data.append(Data(header.utf8))

            var currentOffset = header.count
            var objectOffsets: [Int] = []

            for obj in objects {
                objectOffsets.append(currentOffset)
                let objData = Data(obj.utf8)
                data.append(objData)
                currentOffset += objData.count
            }

            let xrefOffset = currentOffset

            var xref = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
            for offset in objectOffsets {
                xref += String(format: "%010d 00000 n \n", offset)
            }
            data.append(Data(xref.utf8))

            let trailer = """
            trailer
            <<
              /Size \(objects.count + 1)
              /Root 1 0 R
            >>
            startxref
            \(xrefOffset)
            %%EOF
            """
            data.append(Data(trailer.utf8))

            return data
        }
    }
}
