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

            case let .dropShadow(path):
                drawDropShadow(of: path, state: op.state, buffer: &currentBuffer)

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

            case let .drawImageProjective(image, rect, transform):
                rasterizeImageProjective(image, in: rect, transform: transform, state: op.state, clipCache: clipCache, buffer: &currentBuffer)

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

        let transformedPath = path.applying(state.transform)

        // Dash lengths and phase are user-space stroke parameters, so scale them to
        // device space like the line width. An empty (or all-zero) pattern strokes
        // solid. Each "on" run is stroked as an open sub-polyline, so the caps apply
        // at the dash ends, matching CoreGraphics. The vector renderers emit dash
        // natively (Canvas setLineDash, PDF `d`, SVG stroke-dasharray); this brings
        // the software oracle to parity.
        let deviceDash = state.dashPattern.contains { $0 > 0 } ? state.dashPattern.map { $0 * scale } : []
        let deviceDashPhase = state.dashPhase * scale

        // The stroke geometry (segment quads, joins, caps, dash) is owned by
        // `Path.strokedOutline`, so a rasterized stroke and a stroked outline cannot drift. Fill
        // it in a single winding pass so overlapping pieces blend exactly once.
        let strokeShape = transformedPath.strokedOutline(
            lineWidth: deviceLineWidth,
            lineCap: state.lineCap,
            lineJoin: state.lineJoin,
            miterLimit: state.miterLimit,
            dashLengths: deviceDash,
            dashPhase: deviceDashPhase
        )
        guard !strokeShape.elements.isEmpty else { return }

        // The shape is in device space, so reset the CTM and carry the
        // pre-transformed clip together.
        var strokeState = state
        strokeState.transform = .identity
        strokeState.clipPath = state.clipPath?.applying(state.transform)
        rasterizeFill(path: strokeShape, state: strokeState, color: color, rule: .winding, clipCache: clipCache, buffer: &buffer)
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
        // the content. Matches CoreGraphicsRenderer's ordering (shadow set before the
        // layer composites); the group alpha fades the shadow together with the
        // content, and the Gaussian blur is approximated by a box blur, so the
        // result is structurally equivalent to the hardware path, not pixel-exact.
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
        compositeShadow(fromCoverage: coverage, shadow: shadow, state: state, into: &parent)
    }

    /// Paints the blurred, offset shadow of a coverage plane in the shadow color,
    /// the shared core of both the transparency-layer shadow (coverage from the
    /// layer's alpha) and `dropShadow` (coverage from an explicit path).
    private func compositeShadow(fromCoverage coverage: [Double], shadow: Shadow, state: GraphicState, into parent: inout [UInt8]) {
        let shadowAlpha = ShadowRasterizer.shadowAlpha(
            coverage: coverage, width: width, height: height, offset: shadow.offset, blur: shadow.blur
        )
        // The shadow keeps the group alpha (so it fades with the content) but drops
        // the layer's own mask: an offset shadow may legitimately fall outside the
        // masked content and should not be re-clipped by it.
        var shadowState = state
        shadowState.maskImage = nil
        shadowState.maskRect = nil
        shadowState.maskTransform = nil
        for y in 0 ..< height {
            for x in 0 ..< width {
                let alpha = shadowAlpha[y * width + x]
                // blendPixel ignores state.shadow, so the shadow does not recurse.
                if alpha > 0 {
                    blendPixel(x: x, y: y, color: shadow.color, state: shadowState, coverage: alpha, buffer: &parent)
                }
            }
        }
    }

    /// Casts the drop shadow of `path` (in user space) using `state.shadow`, with no
    /// body painted: the silhouette is rasterized, then blurred and offset by the
    /// shared shadow kernel. Like the transparency-layer shadow, the shadow itself is
    /// not re-clipped by the current clip path.
    private func drawDropShadow(of path: Path, state: GraphicState, buffer: inout [UInt8]) {
        guard let shadow = state.shadow else { return }
        let transformedPath = path.applying(state.transform)
        let rasterizer = CoverageRasterizer(canvasWidth: width, canvasHeight: height)
        guard let map = rasterizer.coverage(of: transformedPath, rule: .winding, antialiased: state.shouldAntialias) else { return }
        var coverage = [Double](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                coverage[y * width + x] = map.value(atX: x, y: y)
            }
        }
        compositeShadow(fromCoverage: coverage, shadow: shadow, state: state, into: &buffer)
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

        /// A W3C separable blend mode (Compositing and Blending Level 1, §8-9, which the
        /// CGBlendMode constants follow) composites a per-channel blend function `b(cs, cd)`
        /// of the *unpremultiplied* source/backdrop colours, folded back into the
        /// premultiplied source-over result: `co = cs·αs·(1-αd) + cd·αd·(1-αs) + αs·αd·b`.
        /// The first two terms are the premultiplied operands already to hand.
        func unpremul(_ premultiplied: Double, _ alpha: Double) -> Double {
            alpha > 0 ? premultiplied / alpha : 0
        }
        func separable(_ b: (_ cs: Double, _ cd: Double) -> Double) {
            let blendedAlpha = srcA * dstA
            outA = srcA + dstA * (1.0 - srcA)
            outR = srcR * (1.0 - dstA) + dstR * (1.0 - srcA) + blendedAlpha * b(unpremul(srcR, srcA), unpremul(dstR, dstA))
            outG = srcG * (1.0 - dstA) + dstG * (1.0 - srcA) + blendedAlpha * b(unpremul(srcG, srcA), unpremul(dstG, dstA))
            outB = srcB * (1.0 - dstA) + dstB * (1.0 - srcA) + blendedAlpha * b(unpremul(srcB, srcA), unpremul(dstB, dstA))
        }
        func hardLight(_ cs: Double, _ cd: Double) -> Double {
            cs <= 0.5 ? 2.0 * cs * cd : 1.0 - 2.0 * (1.0 - cs) * (1.0 - cd)
        }

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

        case .screen:
            separable { cs, cd in cs + cd - cs * cd }

        case .overlay:
            // Overlay keys on the backdrop: HardLight with the operands swapped.
            separable { cs, cd in hardLight(cd, cs) }

        case .darken:
            separable { cs, cd in min(cs, cd) }

        case .lighten:
            separable { cs, cd in max(cs, cd) }

        case .colorDodge:
            separable { cs, cd in cd <= 0 ? 0 : (cs >= 1 ? 1 : min(1.0, cd / (1.0 - cs))) }

        case .colorBurn:
            separable { cs, cd in cd >= 1 ? 1 : (cs <= 0 ? 0 : 1.0 - min(1.0, (1.0 - cd) / cs)) }

        case .hardLight:
            separable { cs, cd in hardLight(cs, cd) }

        case .softLight:
            separable { cs, cd in
                let d = cd <= 0.25 ? ((16.0 * cd - 12.0) * cd + 4.0) * cd : cd.squareRoot()
                return cs <= 0.5 ? cd - (1.0 - 2.0 * cs) * cd * (1.0 - cd) : cd + (2.0 * cs - 1.0) * (d - cd)
            }

        case .difference:
            separable { cs, cd in abs(cs - cd) }

        case .exclusion:
            separable { cs, cd in cs + cd - 2.0 * cs * cd }

        case .plusLighter:
            // Porter-Duff "plus": premultiplied channels add and clamp to 1 (additive glow).
            outA = min(1.0, srcA + dstA)
            outR = min(1.0, srcR + dstR)
            outG = min(1.0, srcG + dstG)
            outB = min(1.0, srcB + dstB)

        case .plusDarker:
            // Apple's plus-darker: the inverse-space sum, `1 - ((1-S) + (1-D))`, clamped.
            outA = min(1.0, srcA + dstA)
            outR = max(0.0, srcR + dstR - 1.0)
            outG = max(0.0, srcG + dstG - 1.0)
            outB = max(0.0, srcB + dstB - 1.0)

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
            // The non-separable modes (hue/saturation/color/luminosity) and the remaining
            // Porter-Duff source/destination compositing operators are not yet implemented
            // in the software rasterizer; they composite source-over until they are. The
            // CoreGraphicsRenderer path handles them via the native CGBlendMode.
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

    /// Draws `image` warped from `rect` onto a device quad through a projective
    /// `transform`, using the shared software texture-mapper so it matches
    /// CoreGraphicsRenderer. The warped pixels composite source-over honoring the
    /// state's alpha, blend mode, mask, and clip path.
    private func rasterizeImageProjective(_ image: Image, in rect: Rect, transform: ProjectiveTransform, state: GraphicState, clipCache: ClipCache, buffer: inout [UInt8]) {
        guard let warped = ProjectiveImageRasterizer.warp(
            image, in: rect, transform: transform, width: width, height: height,
            quality: state.interpolationQuality, antialiased: state.shouldAntialias
        ) else { return }
        // The clip path is honored here so the bitmap path matches CoreGraphics,
        // which clips this op through the native gstate.
        let clipPath = state.clipPath?.applying(state.transform)
        let clipCoverage = clipPath.flatMap { cachedClipCoverage($0, antialiased: false, cache: clipCache) }
        if clipPath != nil, clipCoverage == nil { return }
        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = (y * width + x) * 4
                let alpha = Double(warped[index + 3]) / 255.0
                guard alpha > 0 else { continue }
                if let clipCoverage, clipCoverage.value(atX: x, y: y) <= 0 { continue }
                // Un-premultiply the warped sample back to a straight color; blendPixel
                // re-applies the alpha (and the state alpha/mask) as coverage.
                let color = Color(
                    red: Double(warped[index]) / 255.0 / alpha,
                    green: Double(warped[index + 1]) / 255.0 / alpha,
                    blue: Double(warped[index + 2]) / 255.0 / alpha,
                    alpha: alpha
                )
                blendPixel(x: x, y: y, color: color, state: state, buffer: &buffer)
            }
        }
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

        /// `interpolationQuality` controls how the *source* is sampled (nearest vs
        /// bilinear); `shouldAntialias` controls *destination-edge coverage*. A pixel
        /// fully inside the (inverse-mapped) image rect needs no coverage work and is
        /// sampled once at its centre, so integer-aligned interior draws are byte-for-
        /// byte unchanged. Only a pixel the rect edge crosses is supersampled on a 4x4
        /// grid and weighted by the fraction of subsamples inside the rect, so a
        /// transformed/non-integer edge fades instead of stepping. This matches
        /// `ProjectiveImageRasterizer`'s coverage sampling at the edge. Without
        /// antialiasing, every pixel takes the binary centre test.
        func sampleCentre(_ x: Int, _ y: Int) {
            let userPt = Point(x: Double(x) + 0.5, y: Double(y) + 0.5).applying(invTransform)
            guard rect.contains(userPt) else { return }
            let u = rect.width > 0 ? (userPt.x - rect.minX) / rect.width : 0.0
            let v = rect.height > 0 ? (userPt.y - rect.minY) / rect.height : 0.0
            blendPixel(x: x, y: y, color: image.sampledColor(u: u, v: v, quality: state.interpolationQuality), state: state, buffer: &buffer)
        }

        let samplesPerAxis = 4
        let step = 1.0 / Double(samplesPerAxis)
        let sampleCount = Double(samplesPerAxis * samplesPerAxis)

        for y in minY ... maxY {
            for x in minX ... maxX {
                if let clipCoverage {
                    guard clipCoverage.value(atX: x, y: y) > 0 else { continue }
                }
                if !state.shouldAntialias {
                    sampleCentre(x, y)
                    continue
                }
                // A pixel whose four corners all map inside the rect is fully covered
                // (the rect is convex), so it needs only a centre sample.
                let corners = [
                    Point(x: Double(x), y: Double(y)), Point(x: Double(x + 1), y: Double(y)),
                    Point(x: Double(x + 1), y: Double(y + 1)), Point(x: Double(x), y: Double(y + 1)),
                ].map { $0.applying(invTransform) }
                if corners.allSatisfy({ rect.contains($0) }) {
                    sampleCentre(x, y)
                    continue
                }

                var inside = 0
                var sumAlpha = 0.0, sumRed = 0.0, sumGreen = 0.0, sumBlue = 0.0
                for subY in 0 ..< samplesPerAxis {
                    for subX in 0 ..< samplesPerAxis {
                        let userPt = Point(
                            x: Double(x) + (Double(subX) + 0.5) * step,
                            y: Double(y) + (Double(subY) + 0.5) * step
                        ).applying(invTransform)
                        guard rect.contains(userPt) else { continue }
                        inside += 1
                        let u = rect.width > 0 ? (userPt.x - rect.minX) / rect.width : 0.0
                        let v = rect.height > 0 ? (userPt.y - rect.minY) / rect.height : 0.0
                        let color = image.sampledColor(u: u, v: v, quality: state.interpolationQuality)
                        // Accumulate premultiplied so the average is coverage-weighted.
                        sumAlpha += color.alpha
                        sumRed += color.red * color.alpha
                        sumGreen += color.green * color.alpha
                        sumBlue += color.blue * color.alpha
                    }
                }
                guard inside > 0, sumAlpha > 0 else { continue }

                // Edge-coverage fraction of the pixel, and the alpha-weighted mean
                // colour of the covered subsamples. `blendPixel` premultiplies by
                // `color.alpha * coverage`, reproducing the projective path's
                // `sum / sampleCount` premultiplied output.
                let coverage = Double(inside) / sampleCount
                let color = Color(
                    red: sumRed / sumAlpha,
                    green: sumGreen / sumAlpha,
                    blue: sumBlue / sumAlpha,
                    alpha: sumAlpha / Double(inside)
                )
                blendPixel(x: x, y: y, color: color, state: state, coverage: coverage, buffer: &buffer)
            }
        }
    }
}
