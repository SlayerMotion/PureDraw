//
//  BitmapRenderer.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
import Validation

/// A renderer that rasterizes a `GraphicsContext` drawing buffer into a raw pixel `Image`.
public final class BitmapRenderer: Renderer, Sendable {
    public typealias Output = Image

    public let width: Int
    public let height: Int
    public let colorSpace: ColorSpace

    /// Guards against unbounded recursion through self-referential layers.
    private let layerDepth: Int

    public init(width: Int, height: Int, colorSpace: ColorSpace = .deviceRGB) {
        self.width = width
        self.height = height
        self.colorSpace = colorSpace
        layerDepth = 0
    }

    private init(width: Int, height: Int, colorSpace: ColorSpace, layerDepth: Int) {
        self.width = width
        self.height = height
        self.colorSpace = colorSpace
        self.layerDepth = layerDepth
    }

    public func draw(_ context: GraphicsContext) throws -> Image {
        guard width > 0, height > 0 else {
            throw ValidationError(
                reason: "BitmapRenderer width and height must be positive",
                at: [ValidationCodingKey("renderer")]
            )
        }

        var currentBuffer = [UInt8](repeating: 0, count: width * height * 4)
        var bufferStack: [[UInt8]] = []
        var beginOpStack: [DrawOperation] = []
        // Each layer rasterizes once per pass; stamps reuse the cached image.
        var layerCache: [ObjectIdentifier: Image] = [:]
        // Reused across operations so repeated identical clips (pattern tiles)
        // rasterize their clip coverage once per pass instead of once per op.
        let clipCache = ClipCache()

        for op in context.textLoweredCommands {
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
                rasterizeFill(path: path, state: op.state, color: op.state.fillColor, rule: rule, clipCache: clipCache, buffer: &currentBuffer)

            case let .stroke(path):
                rasterizeStroke(path: path, state: op.state, color: op.state.strokeColor, clipCache: clipCache, buffer: &currentBuffer)

            case let .drawLinearGradient(grad, start, end, _):
                rasterizeLinearGradient(grad: grad, start: start, end: end, state: op.state, clipCache: clipCache, buffer: &currentBuffer)

            case let .drawRadialGradient(grad, startCenter, startRadius, endCenter, endRadius, _):
                rasterizeRadialGradient(
                    grad: grad,
                    startCenter: startCenter,
                    startRadius: startRadius,
                    endCenter: endCenter,
                    endRadius: endRadius,
                    state: op.state,
                    clipCache: clipCache,
                    buffer: &currentBuffer
                )

            case let .drawImage(image, rect):
                rasterizeImage(image, in: rect, state: op.state, clipCache: clipCache, buffer: &currentBuffer)

            case let .drawLayer(layer, rect):
                guard layerDepth < 8, layer.width > 0, layer.height > 0 else { continue }
                let key = ObjectIdentifier(layer)
                let stamp: Image
                if let cached = layerCache[key] {
                    stamp = cached
                } else {
                    let layerRenderer = BitmapRenderer(
                        width: max(1, Int(layer.width.rounded(.up))),
                        height: max(1, Int(layer.height.rounded(.up))),
                        colorSpace: colorSpace,
                        layerDepth: layerDepth + 1
                    )
                    stamp = try layerRenderer.draw(layer.context)
                    layerCache[key] = stamp
                }
                rasterizeImage(stamp, in: rect, state: op.state, clipCache: clipCache, buffer: &currentBuffer)

            case .showText:
                break // lowered to fills/strokes by textLoweredCommands
            }
        }

        return try Image(
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

    private func rasterizeFill(path: Path, state: GraphicState, color: Color, rule: FillRule, clipCache: ClipCache, buffer: inout [UInt8]) {
        let transformedPath = path.applying(state.transform)
        let rasterizer = CoverageRasterizer(canvasWidth: width, canvasHeight: height)
        guard let pathCoverage = rasterizer.coverage(of: transformedPath, rule: rule, antialiased: state.shouldAntialias) else { return }

        var clipCoverage: CoverageRasterizer.CoverageMap?
        if let clip = state.clipPath?.applying(state.transform) {
            guard let coverage = cachedClipCoverage(clip, antialiased: state.shouldAntialias, cache: clipCache) else { return }
            clipCoverage = coverage
        }

        for y in pathCoverage.minY ..< pathCoverage.minY + pathCoverage.height {
            for x in pathCoverage.minX ..< pathCoverage.minX + pathCoverage.width {
                var coverage = pathCoverage.value(atX: x, y: y)
                guard coverage > 0 else { continue }
                if let clipCoverage {
                    coverage *= clipCoverage.value(atX: x, y: y)
                    guard coverage > 0 else { continue }
                }
                blendPixel(x: x, y: y, color: color, state: state, coverage: coverage, buffer: &buffer)
            }
        }
    }

    private func rasterizeStroke(path: Path, state: GraphicState, color: Color, clipCache: ClipCache, buffer: inout [UInt8]) {
        let scale = sqrt(abs(state.transform.a * state.transform.d - state.transform.b * state.transform.c))
        let deviceLineWidth = max(0.5, state.lineWidth * scale)
        let halfW = deviceLineWidth / 2.0

        let transformedPath = path.applying(state.transform)

        // Build one winding-consistent shape for the whole stroke (segment
        // quads, joins, caps) and fill it in a single coverage pass, so
        // overlapping pieces blend exactly once.
        var strokeShape = Path()
        for polyline in transformedPath.toPolylines() {
            appendStrokeGeometry(
                for: polyline,
                halfW: halfW,
                lineCap: state.lineCap,
                lineJoin: state.lineJoin,
                miterLimit: state.miterLimit,
                into: &strokeShape
            )
        }
        guard !strokeShape.elements.isEmpty else { return }

        // The shape is in device space, so reset the CTM and carry the
        // pre-transformed clip together.
        var strokeState = state
        strokeState.transform = .identity
        strokeState.clipPath = state.clipPath?.applying(state.transform)
        rasterizeFill(path: strokeShape, state: strokeState, color: color, rule: .winding, clipCache: clipCache, buffer: &buffer)
    }

    private func appendStrokeGeometry(
        for polyline: (points: [Point], isClosed: Bool),
        halfW: Double,
        lineCap: LineCap,
        lineJoin: LineJoin,
        miterLimit: Double,
        into shape: inout Path
    ) {
        // Collapse consecutive duplicates so joins are well defined.
        var points: [Point] = []
        for point in polyline.points where point != points.last {
            points.append(point)
        }
        var isClosed = polyline.isClosed
        if isClosed, points.count >= 2, points.first == points.last {
            points.removeLast()
        }
        if isClosed, points.count < 3 {
            isClosed = false
        }

        guard points.count >= 2 else {
            if points.count == 1, lineCap == .round {
                appendDisk(center: points[0], radius: halfW, into: &shape)
            }
            return
        }

        let segmentCount = isClosed ? points.count : points.count - 1
        for i in 0 ..< segmentCount {
            appendSegmentQuad(a: points[i], b: points[(i + 1) % points.count], halfW: halfW, into: &shape)
        }

        let joinIndices = isClosed ? Array(0 ..< points.count) : Array(1 ..< points.count - 1)
        for i in joinIndices {
            let previous = points[(i - 1 + points.count) % points.count]
            let next = points[(i + 1) % points.count]
            appendJoin(at: points[i], from: previous, to: next, halfW: halfW, lineJoin: lineJoin, miterLimit: miterLimit, into: &shape)
        }

        if !isClosed {
            appendCap(at: points[0], awayFrom: points[1], halfW: halfW, lineCap: lineCap, into: &shape)
            appendCap(at: points[points.count - 1], awayFrom: points[points.count - 2], halfW: halfW, lineCap: lineCap, into: &shape)
        }
    }

    /// Appends the rectangle covering a stroked segment. Vertex order keeps a
    /// positive orientation for any direction, which the winding-rule union
    /// of the stroke shape relies on.
    private func appendSegmentQuad(a: Point, b: Point, halfW: Double, into shape: inout Path) {
        let deltaX = b.x - a.x
        let deltaY = b.y - a.y
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1e-9 else { return }

        let nx = -deltaY / length * halfW
        let ny = deltaX / length * halfW

        shape.move(to: Point(x: a.x + nx, y: a.y + ny))
        shape.addLine(to: Point(x: a.x - nx, y: a.y - ny))
        shape.addLine(to: Point(x: b.x - nx, y: b.y - ny))
        shape.addLine(to: Point(x: b.x + nx, y: b.y + ny))
        shape.closeSubpath()
    }

    private func appendDisk(center: Point, radius: Double, into shape: inout Path) {
        let segments = max(16, min(64, Int(ceil(radius * 4.0))))
        shape.move(to: Point(x: center.x + radius, y: center.y))
        for step in 1 ..< segments {
            let angle = 2.0 * Double.pi * Double(step) / Double(segments)
            shape.addLine(to: Point(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
        }
        shape.closeSubpath()
    }

    private func appendJoin(
        at pt: Point,
        from previous: Point,
        to next: Point,
        halfW: Double,
        lineJoin: LineJoin,
        miterLimit: Double,
        into shape: inout Path
    ) {
        let inX = pt.x - previous.x
        let inY = pt.y - previous.y
        let outX = next.x - pt.x
        let outY = next.y - pt.y
        let inLength = sqrt(inX * inX + inY * inY)
        let outLength = sqrt(outX * outX + outY * outY)
        guard inLength > 1e-9, outLength > 1e-9 else { return }

        let d1 = Point(x: inX / inLength, y: inY / inLength)
        let d2 = Point(x: outX / outLength, y: outY / outLength)
        let turn = d1.x * d2.y - d1.y * d2.x
        guard abs(turn) > 1e-12 else { return } // Collinear: the quads already overlap.

        if lineJoin == .round {
            appendDisk(center: pt, radius: halfW, into: &shape)
            return
        }

        // Outer normals point away from the inside of the turn; the wedge gap
        // between the two segment quads opens on that side.
        let outer1: Point
        let outer2: Point
        if turn > 0 {
            outer1 = Point(x: d1.y, y: -d1.x)
            outer2 = Point(x: d2.y, y: -d2.x)
        } else {
            outer1 = Point(x: -d1.y, y: d1.x)
            outer2 = Point(x: -d2.y, y: d2.x)
        }
        let corner1 = Point(x: pt.x + outer1.x * halfW, y: pt.y + outer1.y * halfW)
        let corner2 = Point(x: pt.x + outer2.x * halfW, y: pt.y + outer2.y * halfW)

        // CoreGraphics compares 1 / sin(half the angle between segments)
        // against the miter limit; cosHalf below equals that sine.
        var miterTip: Point?
        if lineJoin == .miter {
            let bisectorX = outer1.x + outer2.x
            let bisectorY = outer1.y + outer2.y
            let bisectorLength = sqrt(bisectorX * bisectorX + bisectorY * bisectorY)
            if bisectorLength > 1e-9 {
                let cosHalf = (bisectorX * outer1.x + bisectorY * outer1.y) / bisectorLength
                if cosHalf > 1e-9, 1.0 / cosHalf <= miterLimit {
                    let reach = halfW / cosHalf
                    miterTip = Point(x: pt.x + bisectorX / bisectorLength * reach, y: pt.y + bisectorY / bisectorLength * reach)
                }
            }
        }

        // Emit with positive orientation so the union stays winding-consistent.
        let orientation = (corner1.x - pt.x) * (corner2.y - pt.y) - (corner1.y - pt.y) * (corner2.x - pt.x)
        let first = orientation >= 0 ? corner1 : corner2
        let second = orientation >= 0 ? corner2 : corner1
        shape.move(to: pt)
        shape.addLine(to: first)
        if let miterTip {
            shape.addLine(to: miterTip)
        }
        shape.addLine(to: second)
        shape.closeSubpath()
    }

    private func appendCap(at end: Point, awayFrom neighbor: Point, halfW: Double, lineCap: LineCap, into shape: inout Path) {
        switch lineCap {
        case .butt:
            return

        case .round:
            appendDisk(center: end, radius: halfW, into: &shape)

        case .square:
            let dirX = end.x - neighbor.x
            let dirY = end.y - neighbor.y
            let length = sqrt(dirX * dirX + dirY * dirY)
            guard length > 1e-9 else { return }
            let capEnd = Point(x: end.x + dirX / length * halfW, y: end.y + dirY / length * halfW)
            appendSegmentQuad(a: end, b: capEnd, halfW: halfW, into: &shape)
        }
    }

    /// A one-entry cache of the most recent device-space clip coverage. Pattern
    /// tiles and other repeated clips share an identical device-space clip path,
    /// so this hits every time after the first and skips re-rasterizing it.
    final class ClipCache {
        var path: Path?
        var antialiased = false
        var coverage: CoverageRasterizer.CoverageMap?
        var valid = false
    }

    /// The clip's coverage map, reused when the device path and antialias mode
    /// match the cached entry. The pixel-center (aliased) rule matches
    /// `contains(center, .winding)` exactly, so gradient/image output is
    /// unchanged.
    private func cachedClipCoverage(_ devicePath: Path, antialiased: Bool, cache: ClipCache) -> CoverageRasterizer.CoverageMap? {
        if cache.valid, cache.antialiased == antialiased, cache.path == devicePath {
            return cache.coverage
        }
        let coverage = CoverageRasterizer(canvasWidth: width, canvasHeight: height)
            .coverage(of: devicePath, rule: .winding, antialiased: antialiased)
        cache.path = devicePath
        cache.antialiased = antialiased
        cache.coverage = coverage
        cache.valid = true
        return coverage
    }

    private func rasterizeLinearGradient(grad: Gradient, start: Point, end: Point, state: GraphicState, clipCache: ClipCache, buffer: inout [UInt8]) {
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

        let clipCoverage = clipPath.flatMap { cachedClipCoverage($0, antialiased: false, cache: clipCache) }
        if clipPath != nil, clipCoverage == nil { return }

        let invTransform = state.transform.inverted()

        for y in minY ... maxY {
            for x in minX ... maxX {
                if let clipCoverage {
                    guard clipCoverage.value(atX: x, y: y) > 0 else { continue }
                }

                let pt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
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

    private func rasterizeRadialGradient(
        grad: Gradient,
        startCenter: Point,
        startRadius: Double,
        endCenter: Point,
        endRadius: Double,
        state: GraphicState,
        clipCache: ClipCache,
        buffer: inout [UInt8]
    ) {
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

        let clipCoverage = clipPath.flatMap { cachedClipCoverage($0, antialiased: false, cache: clipCache) }
        if clipPath != nil, clipCoverage == nil { return }

        let invTransform = state.transform.inverted()

        for y in minY ... maxY {
            for x in minX ... maxX {
                if let clipCoverage {
                    guard clipCoverage.value(atX: x, y: y) > 0 else { continue }
                }

                let pt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
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
        // A transparency layer's shadow is cast by the composited silhouette: blur
        // and offset the layer's alpha, then paint it in the shadow color beneath
        // the content. Matches CoreGraphicsRenderer's order (shadow set before the
        // layer composites), approximating its Gaussian blur with a box blur.
        if let shadow = state.shadow {
            compositeShadow(of: layer, shadow: shadow, state: state, into: &parent)
        }
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

    /// Composites a blurred, offset silhouette of `layer`'s alpha in the shadow
    /// color beneath the layer's content. The box blur approximates CoreGraphics's
    /// Gaussian shadow: the software path is structurally equivalent, not
    /// pixel-identical (as is already the case among PureDraw's other renderers).
    private func compositeShadow(of layer: [UInt8], shadow: Shadow, state: GraphicState, into parent: inout [UInt8]) {
        var coverage = [Double](repeating: 0, count: width * height)
        for i in 0 ..< width * height {
            coverage[i] = Double(layer[i * 4 + 3]) / 255.0
        }
        let blurred = boxBlurredAlpha(coverage, radius: Int(shadow.blur.rounded()))
        let dx = Int(shadow.offset.x.rounded())
        let dy = Int(shadow.offset.y.rounded())
        for y in 0 ..< height {
            for x in 0 ..< width {
                let sx = x - dx
                let sy = y - dy
                guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                let alpha = blurred[sy * width + sx]
                // blendPixel ignores state.shadow, so the shadow does not recurse.
                if alpha > 0 {
                    blendPixel(x: x, y: y, color: shadow.color, state: state, coverage: alpha, buffer: &parent)
                }
            }
        }
    }

    /// A separable box blur of an alpha plane, clamping at the edges. The identity
    /// when `radius <= 0`.
    private func boxBlurredAlpha(_ source: [Double], radius: Int) -> [Double] {
        guard radius > 0 else { return source }
        let window = Double(radius * 2 + 1)
        var horizontal = [Double](repeating: 0, count: source.count)
        for y in 0 ..< height {
            for x in 0 ..< width {
                var sum = 0.0
                for k in -radius ... radius {
                    let xx = min(width - 1, max(0, x + k))
                    sum += source[y * width + xx]
                }
                horizontal[y * width + x] = sum / window
            }
        }
        var blurred = [Double](repeating: 0, count: source.count)
        for x in 0 ..< width {
            for y in 0 ..< height {
                var sum = 0.0
                for k in -radius ... radius {
                    let yy = min(height - 1, max(0, y + k))
                    sum += horizontal[yy * width + x]
                }
                blurred[y * width + x] = sum / window
            }
        }
        return blurred
    }

    private func blendPixel(x: Int, y: Int, color: Color, state: GraphicState, coverage: Double = 1.0, buffer: inout [UInt8]) {
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
                maskAlpha = maskImage.maskCoverage(x: srcX, y: srcY)
            } else {
                maskAlpha = 0.0
            }
        }

        let srcA = color.alpha * state.alpha * maskAlpha * coverage
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

    private func rasterizeImage(_ image: Image, in rect: Rect, state: GraphicState, clipCache: ClipCache, buffer: inout [UInt8]) {
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
        let clipCoverage = clipPath.flatMap { cachedClipCoverage($0, antialiased: false, cache: clipCache) }
        if clipPath != nil, clipCoverage == nil { return }

        for y in minY ... maxY {
            for x in minX ... maxX {
                if let clipCoverage {
                    guard clipCoverage.value(atX: x, y: y) > 0 else { continue }
                }

                let pt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
                let userPt = pt.applying(invTransform)

                if rect.contains(userPt) {
                    let u = rect.width > 0 ? (userPt.x - rect.minX) / rect.width : 0.0
                    let v = rect.height > 0 ? (userPt.y - rect.minY) / rect.height : 0.0

                    let color = image.sampledColor(u: u, v: v, quality: state.interpolationQuality)
                    blendPixel(x: x, y: y, color: color, state: state, buffer: &buffer)
                }
            }
        }
    }
}
