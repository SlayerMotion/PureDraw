//
//  BitmapRenderer.swift
//  PureDraw
//

import Core
import Foundation
import Geometry

/// A renderer that rasterizes a `GraphicsContext` drawing buffer into a raw pixel `Image`.
public final class BitmapRenderer: Renderer, Sendable {
    public typealias Output = Image

    public let width: Int
    public let height: Int
    public let colorSpace: ColorSpace

    public init(width: Int, height: Int, colorSpace: ColorSpace = .deviceRGB) {
        self.width = width
        self.height = height
        self.colorSpace = colorSpace
    }

    public func render(_ context: GraphicsContext) throws -> Image {
        var currentBuffer = [UInt8](repeating: 0, count: width * height * 4)
        var bufferStack: [[UInt8]] = []
        var beginOpStack: [DrawOperation] = []

        for op in context.commands {
            switch op.kind {
            case .beginTransparencyLayer:
                bufferStack.append(currentBuffer)
                beginOpStack.append(op)
                currentBuffer = [UInt8](repeating: 0, count: width * height * 4)

            case .endTransparencyLayer:
                guard !bufferStack.isEmpty, !beginOpStack.isEmpty else { continue }
                let parentBuffer = bufferStack.removeLast()
                let beginOp = beginOpStack.removeLast()
                var newParentBuffer = parentBuffer
                compositeLayer(currentBuffer, into: &newParentBuffer, state: beginOp.state)
                currentBuffer = newParentBuffer

            case let .fill(path, rule):
                rasterizeFill(path: path, state: op.state, color: op.state.fillColor, rule: rule, buffer: &currentBuffer)

            case let .stroke(path):
                rasterizeStroke(path: path, state: op.state, color: op.state.strokeColor, buffer: &currentBuffer)

            case let .drawLinearGradient(grad, start, end, _):
                rasterizeLinearGradient(grad: grad, start: start, end: end, state: op.state, buffer: &currentBuffer)

            case let .drawRadialGradient(grad, startCenter, startRadius, endCenter, endRadius, _):
                rasterizeRadialGradient(
                    grad: grad,
                    startCenter: startCenter,
                    startRadius: startRadius,
                    endCenter: endCenter,
                    endRadius: endRadius,
                    state: op.state,
                    buffer: &currentBuffer
                )

            case let .drawImage(image, rect):
                rasterizeImage(image, in: rect, state: op.state, buffer: &currentBuffer)
            }
        }

        return Image(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            colorSpace: colorSpace,
            alphaInfo: .premultipliedLast,
            data: currentBuffer
        )
    }

    // MARK: - Rasterization Helpers

    private func rasterizeFill(path: Path, state: GraphicState, color: Color, rule: FillRule, buffer: inout [UInt8]) {
        let transformedPath = path.applying(state.transform)
        let bbox = transformedPath.boundingBox
        guard !bbox.isNull, !bbox.isEmpty else { return }

        let clipPath = state.clipPath?.applying(state.transform)

        let minX = max(0, Int(floor(bbox.minX)))
        let maxX = min(width - 1, Int(ceil(bbox.maxX)))
        let minY = max(0, Int(floor(bbox.minY)))
        let maxY = min(height - 1, Int(ceil(bbox.maxY)))

        guard minX <= maxX, minY <= maxY else { return }

        for y in minY ... maxY {
            for x in minX ... maxX {
                let pt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
                if transformedPath.contains(pt, using: rule) {
                    if let clip = clipPath {
                        guard clip.contains(pt, using: .winding) else { continue }
                    }
                    blendPixel(x: x, y: y, color: color, state: state, buffer: &buffer)
                }
            }
        }
    }

    private func rasterizeStroke(path: Path, state: GraphicState, color: Color, buffer: inout [UInt8]) {
        let scale = sqrt(abs(state.transform.a * state.transform.d - state.transform.b * state.transform.c))
        let deviceLineWidth = max(0.5, state.lineWidth * scale)
        let halfW = deviceLineWidth / 2.0

        let transformedPath = path.applying(state.transform)
        let polygons = transformedPath.toPolygons()

        let clipPath = state.clipPath?.applying(state.transform)

        for poly in polygons {
            guard poly.count >= 2 else {
                if poly.count == 1, state.lineCap == .round {
                    drawDisk(center: poly[0], radius: halfW, color: color, state: state, clipPath: clipPath, buffer: &buffer)
                }
                continue
            }

            for i in 0 ..< (poly.count - 1) {
                let a = poly[i]
                let b = poly[i + 1]
                drawSegment(a: a, b: b, halfW: halfW, color: color, state: state, clipPath: clipPath, buffer: &buffer)
            }

            for i in 0 ..< poly.count {
                let pt = poly[i]
                let isStart = (i == 0)
                let isEnd = (i == poly.count - 1)

                if isStart || isEnd {
                    switch state.lineCap {
                    case .round:
                        drawDisk(center: pt, radius: halfW, color: color, state: state, clipPath: clipPath, buffer: &buffer)
                    case .square:
                        drawSquareCap(pt: pt, index: i, poly: poly, halfW: halfW, color: color, state: state, clipPath: clipPath, buffer: &buffer)
                    case .butt:
                        break
                    }
                } else {
                    switch state.lineJoin {
                    case .round:
                        drawDisk(center: pt, radius: halfW, color: color, state: state, clipPath: clipPath, buffer: &buffer)
                    case .miter, .bevel:
                        drawDisk(center: pt, radius: halfW, color: color, state: state, clipPath: clipPath, buffer: &buffer)
                    }
                }
            }
        }
    }

    private func drawDisk(center: Point, radius: Double, color: Color, state: GraphicState, clipPath: Path?, buffer: inout [UInt8]) {
        let minX = max(0, Int(floor(center.x - radius)))
        let maxX = min(width - 1, Int(ceil(center.x + radius)))
        let minY = max(0, Int(floor(center.y - radius)))
        let maxY = min(height - 1, Int(ceil(center.y + radius)))

        guard minX <= maxX, minY <= maxY else { return }

        let r2 = radius * radius
        for y in minY ... maxY {
            for x in minX ... maxX {
                let deltaX = Double(x) + 0.5 - center.x
                let deltaY = Double(y) + 0.5 - center.y
                if deltaX * deltaX + deltaY * deltaY <= r2 {
                    let pt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
                    if let clip = clipPath {
                        guard clip.contains(pt, using: .winding) else { continue }
                    }
                    blendPixel(x: x, y: y, color: color, state: state, buffer: &buffer)
                }
            }
        }
    }

    private func drawSegment(a: Point, b: Point, halfW: Double, color: Color, state: GraphicState, clipPath _: Path?, buffer: inout [UInt8]) {
        let deltaX = b.x - a.x
        let deltaY = b.y - a.y
        let len = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard len > 1e-9 else { return }

        let nx = -deltaY / len
        let ny = deltaX / len

        let p0 = Point(x: a.x + nx * halfW, y: a.y + ny * halfW)
        let p1 = Point(x: a.x - nx * halfW, y: a.y - ny * halfW)
        let p2 = Point(x: b.x - nx * halfW, y: b.y - ny * halfW)
        let p3 = Point(x: b.x + nx * halfW, y: b.y + ny * halfW)

        var rectPath = Path()
        rectPath.move(to: p0)
        rectPath.addLine(to: p1)
        rectPath.addLine(to: p2)
        rectPath.addLine(to: p3)
        rectPath.closeSubpath()

        var segmentState = state
        segmentState.transform = .identity
        rasterizeFill(path: rectPath, state: segmentState, color: color, rule: .winding, buffer: &buffer)
    }

    private func drawSquareCap(pt: Point, index: Int, poly: [Point], halfW: Double, color: Color, state: GraphicState, clipPath _: Path?, buffer: inout [UInt8]) {
        let isStart = (index == 0)
        let neighbor = isStart ? poly[1] : poly[poly.count - 2]

        let deltaX = neighbor.x - pt.x
        let deltaY = neighbor.y - pt.y
        let len = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard len > 1e-9 else { return }

        let dirX = isStart ? -deltaX / len : deltaX / len
        let dirY = isStart ? -deltaY / len : deltaY / len

        let nx = -dirY
        let ny = dirX

        let capEnd = Point(x: pt.x + dirX * halfW, y: pt.y + dirY * halfW)

        let p0 = Point(x: pt.x + nx * halfW, y: pt.y + ny * halfW)
        let p1 = Point(x: pt.x - nx * halfW, y: pt.y - ny * halfW)
        let p2 = Point(x: capEnd.x - nx * halfW, y: capEnd.y - ny * halfW)
        let p3 = Point(x: capEnd.x + nx * halfW, y: capEnd.y + ny * halfW)

        var capPath = Path()
        capPath.move(to: p0)
        capPath.addLine(to: p1)
        capPath.addLine(to: p2)
        capPath.addLine(to: p3)
        capPath.closeSubpath()

        var capState = state
        capState.transform = .identity
        rasterizeFill(path: capPath, state: capState, color: color, rule: .winding, buffer: &buffer)
    }

    private func rasterizeLinearGradient(grad: Gradient, start: Point, end: Point, state: GraphicState, buffer: inout [UInt8]) {
        let clipPath = state.clipPath?.applying(state.transform)
        let bounds = clipPath?.boundingBox ?? Rect(x: 0, y: 0, width: Double(width), height: Double(height))

        let minX = max(0, Int(floor(bounds.minX)))
        let maxX = min(width - 1, Int(ceil(bounds.maxX)))
        let minY = max(0, Int(floor(bounds.minY)))
        let maxY = min(height - 1, Int(ceil(bounds.maxY)))

        guard minX <= maxX, minY <= maxY else { return }

        let gradVec = Point(x: end.x - start.x, y: end.y - start.y)
        let gradLenSq = gradVec.x * gradVec.x + gradVec.y * gradVec.y
        guard gradLenSq > 1e-9 else { return }

        let invTransform = state.transform.inverted()

        for y in minY ... maxY {
            for x in minX ... maxX {
                let pt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)

                if let clip = clipPath {
                    guard clip.contains(pt, using: .winding) else { continue }
                }

                let userPt = pt.applying(invTransform)
                let projX = userPt.x - start.x
                let projY = userPt.y - start.y
                let dot = projX * gradVec.x + projY * gradVec.y
                var paramT = dot / gradLenSq
                paramT = min(1.0, max(0.0, paramT))

                let color = interpolateGradient(grad, at: paramT)
                blendPixel(x: x, y: y, color: color, state: state, buffer: &buffer)
            }
        }
    }

    private func rasterizeRadialGradient(grad: Gradient, startCenter: Point, startRadius: Double, endCenter: Point, endRadius: Double, state: GraphicState, buffer: inout [UInt8]) {
        let clipPath = state.clipPath?.applying(state.transform)
        let bounds = clipPath?.boundingBox ?? Rect(x: 0, y: 0, width: Double(width), height: Double(height))

        let minX = max(0, Int(floor(bounds.minX)))
        let maxX = min(width - 1, Int(ceil(bounds.maxX)))
        let minY = max(0, Int(floor(bounds.minY)))
        let maxY = min(height - 1, Int(ceil(bounds.maxY)))

        guard minX <= maxX, minY <= maxY else { return }

        let diffCenter = Point(x: endCenter.x - startCenter.x, y: endCenter.y - startCenter.y)
        let diffRadius = endRadius - startRadius

        let dcLenSq = diffCenter.x * diffCenter.x + diffCenter.y * diffCenter.y
        let coeffA = dcLenSq - diffRadius * diffRadius

        let invTransform = state.transform.inverted()

        for y in minY ... maxY {
            for x in minX ... maxX {
                let pt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)

                if let clip = clipPath {
                    guard clip.contains(pt, using: .winding) else { continue }
                }

                let userPt = pt.applying(invTransform)
                let v = Point(x: userPt.x - startCenter.x, y: userPt.y - startCenter.y)

                let coeffB = -2.0 * (v.x * diffCenter.x + v.y * diffCenter.y + startRadius * diffRadius)
                let coeffC = (v.x * v.x + v.y * v.y) - startRadius * startRadius

                var paramT: Double?

                if abs(coeffA) < 1e-9 {
                    if abs(coeffB) > 1e-9 {
                        paramT = -coeffC / coeffB
                    }
                } else {
                    let disc = coeffB * coeffB - 4.0 * coeffA * coeffC
                    if disc >= 0 {
                        let sqrtDisc = sqrt(disc)
                        let t1 = (-coeffB + sqrtDisc) / (2.0 * coeffA)
                        let t2 = (-coeffB - sqrtDisc) / (2.0 * coeffA)

                        let r1 = startRadius + t1 * diffRadius
                        let r2 = startRadius + t2 * diffRadius

                        if r1 >= 0, r2 >= 0 {
                            paramT = max(t1, t2)
                        } else if r1 >= 0 {
                            paramT = t1
                        } else if r2 >= 0 {
                            paramT = t2
                        }
                    }
                }

                if let valT = paramT {
                    let clampedT = min(1.0, max(0.0, valT))
                    let color = interpolateGradient(grad, at: clampedT)
                    blendPixel(x: x, y: y, color: color, state: state, buffer: &buffer)
                }
            }
        }
    }

    private func interpolateGradient(_ grad: Gradient, at t: Double) -> Color {
        guard !grad.stops.isEmpty else { return .black }
        if grad.stops.count == 1 { return grad.stops[0].color }

        let sorted = grad.stops.sorted(by: { $0.location < $1.location })

        guard let first = sorted.first, let last = sorted.last else {
            return .black
        }

        if t <= first.location {
            return first.color
        }
        if t >= last.location {
            return last.color
        }

        for i in 0 ..< (sorted.count - 1) {
            let left = sorted[i]
            let right = sorted[i + 1]
            if left.location <= t, t <= right.location {
                let diff = right.location - left.location
                let ratio = diff > 0 ? (t - left.location) / diff : 0.0

                let r = left.color.red + ratio * (right.color.red - left.color.red)
                let g = left.color.green + ratio * (right.color.green - left.color.green)
                let b = left.color.blue + ratio * (right.color.blue - left.color.blue)
                let a = left.color.alpha + ratio * (right.color.alpha - left.color.alpha)

                return Color(red: r, green: g, blue: b, alpha: a)
            }
        }

        return .black
    }

    private func compositeLayer(_ layer: [UInt8], into parent: inout [UInt8], state: GraphicState) {
        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = (y * width + x) * 4
                let srcA = Double(layer[index + 3]) / 255.0
                if srcA > 0 {
                    let srcR = srcA > 0 ? (Double(layer[index]) / 255.0) / srcA : 0.0
                    let srcG = srcA > 0 ? (Double(layer[index + 1]) / 255.0) / srcA : 0.0
                    let srcB = srcA > 0 ? (Double(layer[index + 2]) / 255.0) / srcA : 0.0

                    let color = Color(red: srcR, green: srcG, blue: srcB, alpha: srcA)
                    blendPixel(x: x, y: y, color: color, state: state, buffer: &parent)
                }
            }
        }
    }

    private func blendPixel(x: Int, y: Int, color: Color, state: GraphicState, buffer: inout [UInt8]) {
        let index = (y * width + x) * 4

        var maskAlpha = 1.0
        if let maskImage = state.maskImage, let maskRect = state.maskRect, let maskTransform = state.maskTransform {
            let pt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
            let invTransform = maskTransform.inverted()
            let userPt = pt.applying(invTransform)
            if maskRect.contains(userPt) {
                let u = maskRect.width > 0 ? (userPt.x - maskRect.minX) / maskRect.width : 0.0
                let v = maskRect.height > 0 ? (userPt.y - maskRect.minY) / maskRect.height : 0.0
                let srcX = min(maskImage.width - 1, max(0, Int(u * Double(maskImage.width))))
                let srcY = min(maskImage.height - 1, max(0, Int(v * Double(maskImage.height))))
                let maskColor = extractPixelColor(from: maskImage, x: srcX, y: srcY)

                let hasAlpha = switch maskImage.alphaInfo {
                case .none, .noneSkipLast, .noneSkipFirst: false
                default: true
                }

                if hasAlpha {
                    maskAlpha = maskColor.alpha
                } else {
                    maskAlpha = 0.2126 * maskColor.red + 0.7152 * maskColor.green + 0.0722 * maskColor.blue
                }
            } else {
                maskAlpha = 0.0
            }
        }

        let srcA = color.alpha * state.alpha * maskAlpha
        let srcR = color.red * srcA
        let srcG = color.green * srcA
        let srcB = color.blue * srcA

        let dstR = Double(buffer[index]) / 255.0
        let dstG = Double(buffer[index + 1]) / 255.0
        let dstB = Double(buffer[index + 2]) / 255.0
        let dstA = Double(buffer[index + 3]) / 255.0

        var outR = 0.0
        var outG = 0.0
        var outB = 0.0
        var outA = 0.0

        switch state.blendMode {
        case .normal:
            outA = srcA + dstA * (1.0 - srcA)
            outR = srcR + dstR * (1.0 - srcA)
            outG = srcG + dstG * (1.0 - srcA)
            outB = srcB + dstB * (1.0 - srcA)

        case .multiply:
            outA = srcA + dstA - srcA * dstA
            outR = srcR * dstR + srcR * (1.0 - dstA) + dstR * (1.0 - srcA)
            outG = srcG * dstG + srcG * (1.0 - dstA) + dstG * (1.0 - srcA)
            outB = srcB * dstB + srcB * (1.0 - dstA) + dstB * (1.0 - srcA)

        case .clear:
            outR = 0
            outG = 0
            outB = 0
            outA = 0

        case .copy:
            outR = srcR
            outG = srcG
            outB = srcB
            outA = srcA

        default:
            outA = srcA + dstA * (1.0 - srcA)
            outR = srcR + dstR * (1.0 - srcA)
            outG = srcG + dstG * (1.0 - srcA)
            outB = srcB + dstB * (1.0 - srcA)
        }

        buffer[index] = UInt8(min(255, max(0, Int(round(outR * 255.0)))))
        buffer[index + 1] = UInt8(min(255, max(0, Int(round(outG * 255.0)))))
        buffer[index + 2] = UInt8(min(255, max(0, Int(round(outB * 255.0)))))
        buffer[index + 3] = UInt8(min(255, max(0, Int(round(outA * 255.0)))))
    }

    private func rasterizeImage(_ image: Image, in rect: Rect, state: GraphicState, buffer: inout [UInt8]) {
        let p0 = Point(x: rect.minX, y: rect.minY)
        let p1 = Point(x: rect.maxX, y: rect.minY)
        let p2 = Point(x: rect.maxX, y: rect.maxY)
        let p3 = Point(x: rect.minX, y: rect.maxY)

        let dp0 = p0.applying(state.transform)
        let dp1 = p1.applying(state.transform)
        let dp2 = p2.applying(state.transform)
        let dp3 = p3.applying(state.transform)

        let minX = max(0, Int(floor(min(dp0.x, dp1.x, dp2.x, dp3.x))))
        let maxX = min(width - 1, Int(ceil(max(dp0.x, dp1.x, dp2.x, dp3.x))))
        let minY = max(0, Int(floor(min(dp0.y, dp1.y, dp2.y, dp3.y))))
        let maxY = min(height - 1, Int(ceil(max(dp0.y, dp1.y, dp2.y, dp3.y))))

        guard minX <= maxX, minY <= maxY else { return }

        let invTransform = state.transform.inverted()
        let clipPath = state.clipPath?.applying(state.transform)

        for y in minY ... maxY {
            for x in minX ... maxX {
                let pt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)

                if let clip = clipPath {
                    guard clip.contains(pt, using: .winding) else { continue }
                }

                let userPt = pt.applying(invTransform)

                if rect.contains(userPt) {
                    let u = rect.width > 0 ? (userPt.x - rect.minX) / rect.width : 0.0
                    let v = rect.height > 0 ? (userPt.y - rect.minY) / rect.height : 0.0

                    let srcX = min(image.width - 1, max(0, Int(u * Double(image.width))))
                    let srcY = min(image.height - 1, max(0, Int(v * Double(image.height))))

                    let color = extractPixelColor(from: image, x: srcX, y: srcY)
                    blendPixel(x: x, y: y, color: color, state: state, buffer: &buffer)
                }
            }
        }
    }

    private func extractPixelColor(from image: Image, x: Int, y: Int) -> Color {
        let bytesPerPixel = image.bitsPerPixel / 8
        let index = y * image.bytesPerRow + x * bytesPerPixel
        guard index + bytesPerPixel <= image.data.count else { return .clear }

        let alphaFirst = image.alphaInfo == .first || image.alphaInfo == .premultipliedFirst || image.alphaInfo == .noneSkipFirst
        let hasAlpha = !(image.alphaInfo == .none || image.alphaInfo == .noneSkipFirst || image.alphaInfo == .noneSkipLast)

        var rawComponents: [Double] = []
        var rawAlpha = 1.0

        switch image.colorSpace {
        case .deviceGray:
            if bytesPerPixel >= 2 {
                if alphaFirst {
                    rawAlpha = Double(image.data[index]) / 255.0
                    rawComponents = [Double(image.data[index + 1]) / 255.0]
                } else {
                    rawComponents = [Double(image.data[index]) / 255.0]
                    rawAlpha = Double(image.data[index + 1]) / 255.0
                }
            } else if bytesPerPixel == 1 {
                rawComponents = [Double(image.data[index]) / 255.0]
                rawAlpha = 1.0
            } else {
                return .clear
            }

        case .deviceRGB:
            if bytesPerPixel >= 4 {
                if alphaFirst {
                    rawAlpha = Double(image.data[index]) / 255.0
                    rawComponents = [
                        Double(image.data[index + 1]) / 255.0,
                        Double(image.data[index + 2]) / 255.0,
                        Double(image.data[index + 3]) / 255.0,
                    ]
                } else {
                    rawComponents = [
                        Double(image.data[index]) / 255.0,
                        Double(image.data[index + 1]) / 255.0,
                        Double(image.data[index + 2]) / 255.0,
                    ]
                    rawAlpha = Double(image.data[index + 3]) / 255.0
                }
            } else if bytesPerPixel == 3 {
                rawComponents = [
                    Double(image.data[index]) / 255.0,
                    Double(image.data[index + 1]) / 255.0,
                    Double(image.data[index + 2]) / 255.0,
                ]
                rawAlpha = 1.0
            } else {
                return .clear
            }

        case .deviceCMYK:
            if bytesPerPixel >= 5 {
                if alphaFirst {
                    rawAlpha = Double(image.data[index]) / 255.0
                    rawComponents = [
                        Double(image.data[index + 1]) / 255.0,
                        Double(image.data[index + 2]) / 255.0,
                        Double(image.data[index + 3]) / 255.0,
                        Double(image.data[index + 4]) / 255.0,
                    ]
                } else {
                    rawComponents = [
                        Double(image.data[index]) / 255.0,
                        Double(image.data[index + 1]) / 255.0,
                        Double(image.data[index + 2]) / 255.0,
                        Double(image.data[index + 3]) / 255.0,
                    ]
                    rawAlpha = Double(image.data[index + 4]) / 255.0
                }
            } else if bytesPerPixel >= 4 {
                rawComponents = [
                    Double(image.data[index]) / 255.0,
                    Double(image.data[index + 1]) / 255.0,
                    Double(image.data[index + 2]) / 255.0,
                    Double(image.data[index + 3]) / 255.0,
                ]
                rawAlpha = 1.0
            } else {
                return .clear
            }
        }

        if let masking = image.maskingColors, masking.count == rawComponents.count * 2 {
            var allMatch = true
            for i in 0 ..< rawComponents.count {
                let val = rawComponents[i]
                let minVal = masking[2 * i]
                let maxVal = masking[2 * i + 1]
                if val < minVal || val > maxVal {
                    allMatch = false
                    break
                }
            }
            if allMatch {
                return .clear
            }
        }

        let finalAlpha = hasAlpha ? rawAlpha : 1.0
        let isPremultiplied = image.alphaInfo == .premultipliedLast || image.alphaInfo == .premultipliedFirst

        switch image.colorSpace {
        case .deviceGray:
            let g = rawComponents[0]
            let finalGray = (isPremultiplied && finalAlpha > 0) ? (g / finalAlpha) : g
            return Color(gray: finalGray, alpha: finalAlpha)

        case .deviceRGB:
            let r = rawComponents[0]
            let g = rawComponents[1]
            let b = rawComponents[2]
            let finalR = (isPremultiplied && finalAlpha > 0) ? (r / finalAlpha) : r
            let finalG = (isPremultiplied && finalAlpha > 0) ? (g / finalAlpha) : g
            let finalB = (isPremultiplied && finalAlpha > 0) ? (b / finalAlpha) : b
            return Color(red: finalR, green: finalG, blue: finalB, alpha: finalAlpha)

        case .deviceCMYK:
            let c = rawComponents[0]
            let m = rawComponents[1]
            let y = rawComponents[2]
            let k = rawComponents[3]
            let finalC = (isPremultiplied && finalAlpha > 0) ? (c / finalAlpha) : c
            let finalM = (isPremultiplied && finalAlpha > 0) ? (m / finalAlpha) : m
            let finalY = (isPremultiplied && finalAlpha > 0) ? (y / finalAlpha) : y
            let finalK = (isPremultiplied && finalAlpha > 0) ? (k / finalAlpha) : k
            return Color(cyan: finalC, magenta: finalM, yellow: finalY, black: finalK, alpha: finalAlpha)
        }
    }
}
