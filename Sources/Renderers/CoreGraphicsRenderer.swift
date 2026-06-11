//
//  CoreGraphicsRenderer.swift
//  PureDraw
//

#if canImport(CoreGraphics)
    import Core
    import CoreGraphics
    import Foundation
    import Geometry

    /// A renderer that executes the PureDraw command buffer on an Apple `CGContext`.
    public struct CoreGraphicsRenderer: Renderer, @unchecked Sendable {
        public typealias Output = Void

        /// The target native CoreGraphics context.
        public let targetContext: CGContext

        /// Guards against unbounded recursion through self-referential layers.
        private let layerDepth: Int

        public init(context: CGContext) {
            targetContext = context
            layerDepth = 0
        }

        private init(context: CGContext, layerDepth: Int) {
            targetContext = context
            self.layerDepth = layerDepth
        }

        public func draw(_ context: GraphicsContext) throws {
            // DeviceGray mask conversion is O(width * height); reuse converted
            // masks across operations within this render pass.
            var maskCache = [(source: Image, mask: CGImage)]()
            // Each layer renders once per pass into a native CGLayer.
            var layerCache: [ObjectIdentifier: CGLayer] = [:]
            for operation in context.textLoweredCommands {
                switch operation.kind {
                case .beginTransparencyLayer:
                    targetContext.saveGState()

                    // Apply CTM & Mask
                    applyCTMAndMask(state: operation.state, maskCache: &maskCache)
                    targetContext.setAlpha(CGFloat(operation.state.alpha))
                    targetContext.setBlendMode(CGBlendMode(from: operation.state.blendMode))

                    // Apply Shadow if present
                    if let shadow = operation.state.shadow {
                        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                        let components = [
                            CGFloat(shadow.color.red),
                            CGFloat(shadow.color.green),
                            CGFloat(shadow.color.blue),
                            CGFloat(shadow.color.alpha),
                        ]
                        if let cgColor = CGColor(colorSpace: colorSpace, components: components) {
                            targetContext.setShadow(
                                offset: CGSize(width: CGFloat(shadow.offset.x), height: CGFloat(shadow.offset.y)),
                                blur: CGFloat(shadow.blur),
                                color: cgColor
                            )
                        }
                    }

                    // Apply Clip Path (if defined)
                    if let clip = operation.state.clipPath {
                        let cgPath = try createCGPath(from: clip)
                        targetContext.addPath(cgPath)
                        targetContext.clip()
                    }

                    targetContext.beginTransparencyLayer(auxiliaryInfo: nil)

                case .endTransparencyLayer:
                    targetContext.endTransparencyLayer()
                    targetContext.restoreGState()

                default:
                    // 1. Push Graphics State
                    targetContext.saveGState()

                    // 2. Apply CTM & Mask & Opacity
                    applyCTMAndMask(state: operation.state, maskCache: &maskCache)
                    targetContext.setAlpha(CGFloat(operation.state.alpha))
                    targetContext.setBlendMode(CGBlendMode(from: operation.state.blendMode))

                    // 3. Apply Style Parameters
                    targetContext.interpolationQuality = CGInterpolationQuality(from: operation.state.interpolationQuality)
                    targetContext.setLineWidth(CGFloat(operation.state.lineWidth))
                    targetContext.setLineCap(CGLineCap(from: operation.state.lineCap))
                    targetContext.setLineJoin(CGLineJoin(from: operation.state.lineJoin))
                    targetContext.setMiterLimit(CGFloat(operation.state.miterLimit))
                    targetContext.setFlatness(CGFloat(operation.state.flatness))

                    if !operation.state.dashPattern.isEmpty {
                        targetContext.setLineDash(
                            phase: CGFloat(operation.state.dashPhase),
                            lengths: operation.state.dashPattern.map { CGFloat($0) }
                        )
                    }

                    // Apply Shadow if present
                    if let shadow = operation.state.shadow {
                        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                        let components = [
                            CGFloat(shadow.color.red),
                            CGFloat(shadow.color.green),
                            CGFloat(shadow.color.blue),
                            CGFloat(shadow.color.alpha),
                        ]
                        if let cgColor = CGColor(colorSpace: colorSpace, components: components) {
                            targetContext.setShadow(
                                offset: CGSize(width: CGFloat(shadow.offset.x), height: CGFloat(shadow.offset.y)),
                                blur: CGFloat(shadow.blur),
                                color: cgColor
                            )
                        }
                    }

                    // 4. Apply Clip Path (if defined)
                    if let clip = operation.state.clipPath {
                        let cgPath = try createCGPath(from: clip)
                        targetContext.addPath(cgPath)
                        targetContext.clip()
                    }

                    // 5. Draw Path Geometry
                    switch operation.kind {
                    case let .fill(path, rule):
                        let cgPath = try createCGPath(from: path)
                        targetContext.addPath(cgPath)
                        let cgFillRule = (rule == .evenOdd) ? CGPathFillRule.evenOdd : CGPathFillRule.winding

                        applyFillColor(operation.state.fillColor)
                        targetContext.fillPath(using: cgFillRule)

                    case let .stroke(path):
                        let cgPath = try createCGPath(from: path)
                        targetContext.addPath(cgPath)

                        applyStrokeColor(operation.state.strokeColor)
                        targetContext.strokePath()

                    case let .drawLinearGradient(grad, start, end, options):
                        let cgGradient = try createCGGradient(from: grad)
                        var cgOptions: CGGradientDrawingOptions = []
                        if options.contains(.drawsBeforeStartLocation) {
                            cgOptions.insert(.drawsBeforeStartLocation)
                        }
                        if options.contains(.drawsAfterEndLocation) {
                            cgOptions.insert(.drawsAfterEndLocation)
                        }
                        targetContext.drawLinearGradient(
                            cgGradient,
                            start: CGPoint(x: CGFloat(start.x), y: CGFloat(start.y)),
                            end: CGPoint(x: CGFloat(end.x), y: CGFloat(end.y)),
                            options: cgOptions
                        )

                    case let .drawRadialGradient(grad, startCenter, startRadius, endCenter, endRadius, options):
                        let cgGradient = try createCGGradient(from: grad)
                        var cgOptions: CGGradientDrawingOptions = []
                        if options.contains(.drawsBeforeStartLocation) {
                            cgOptions.insert(.drawsBeforeStartLocation)
                        }
                        if options.contains(.drawsAfterEndLocation) {
                            cgOptions.insert(.drawsAfterEndLocation)
                        }
                        targetContext.drawRadialGradient(
                            cgGradient,
                            startCenter: CGPoint(x: CGFloat(startCenter.x), y: CGFloat(startCenter.y)),
                            startRadius: CGFloat(startRadius),
                            endCenter: CGPoint(x: CGFloat(endCenter.x), y: CGFloat(endCenter.y)),
                            endRadius: CGFloat(endRadius),
                            options: cgOptions
                        )

                    case let .drawImage(image, rect):
                        if let cgImage = createCGImage(from: image) {
                            targetContext.saveGState()
                            targetContext.translateBy(x: CGFloat(rect.origin.x), y: CGFloat(rect.origin.y + rect.height))
                            targetContext.scaleBy(x: 1.0, y: -1.0)
                            targetContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(rect.width), height: CGFloat(rect.height)))
                            targetContext.restoreGState()
                        }

                    case let .drawLayer(layer, rect):
                        guard layerDepth < 8, layer.width > 0, layer.height > 0 else { break }
                        let key = ObjectIdentifier(layer)
                        if layerCache[key] == nil,
                           let cgLayer = CGLayer(targetContext, size: CGSize(width: layer.width, height: layer.height), auxiliaryInfo: nil),
                           let layerContext = cgLayer.context
                        {
                            try CoreGraphicsRenderer(context: layerContext, layerDepth: layerDepth + 1).draw(layer.context)
                            layerCache[key] = cgLayer
                        }
                        if let cgLayer = layerCache[key] {
                            targetContext.draw(cgLayer, in: CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height))
                        }

                    case let .dropShadow(path):
                        drawDropShadow(of: path, state: operation.state)

                    case let .drawImageProjective(image, rect, transform):
                        drawImageProjective(image, in: rect, transform: transform, state: operation.state)

                    case .beginTransparencyLayer, .endTransparencyLayer, .showText:
                        break
                    }

                    // 6. Pop Graphics State
                    targetContext.restoreGState()
                }
            }
        }

        private enum RenderingError: Error {
            case cannotCreateColorSpace
            case cannotCreateGradient
        }

        /// Draws `image` warped onto a device quad through a projective `transform`.
        /// CoreGraphics has no native projective image draw, so the warp is computed
        /// in software (the shared texture-mapper, matching BitmapRenderer) and the
        /// finished device-space image is blitted under the identity CTM.
        private func drawImageProjective(_ image: Image, in rect: Rect, transform: ProjectiveTransform, state: GraphicState) {
            let canvasWidth = targetContext.width
            let canvasHeight = targetContext.height
            guard canvasWidth > 0, canvasHeight > 0 else { return }
            guard let data = ProjectiveImageRasterizer.warp(
                image, in: rect, transform: transform, width: canvasWidth, height: canvasHeight, quality: state.interpolationQuality
            ) else { return }
            guard let warped = try? Image(
                width: canvasWidth, height: canvasHeight, alphaInfo: .premultipliedLast, data: data
            ), let cgImage = createCGImage(from: warped) else { return }
            targetContext.saveGState()
            targetContext.setAlpha(CGFloat(state.alpha))
            targetContext.setBlendMode(.normal)
            targetContext.concatenate(targetContext.ctm.inverted())
            targetContext.translateBy(x: 0, y: CGFloat(canvasHeight))
            targetContext.scaleBy(x: 1, y: -1)
            targetContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)))
            targetContext.restoreGState()
        }

        /// Casts the drop shadow of `path` using the shared software shadow kernel, so
        /// it matches `BitmapRenderer`. CoreGraphics cannot cast a shadow without also
        /// painting the shape, so the shadow is computed in software and composited as
        /// a device-space image.
        private func drawDropShadow(of path: Path, state: GraphicState) {
            guard let shadow = state.shadow else { return }
            let canvasWidth = targetContext.width
            let canvasHeight = targetContext.height
            guard canvasWidth > 0, canvasHeight > 0 else { return }
            let transformedPath = path.applying(state.transform)
            let rasterizer = CoverageRasterizer(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
            guard let map = rasterizer.coverage(of: transformedPath, rule: .winding, antialiased: state.shouldAntialias) else { return }
            var coverage = [Double](repeating: 0, count: canvasWidth * canvasHeight)
            for y in 0 ..< canvasHeight {
                for x in 0 ..< canvasWidth {
                    coverage[y * canvasWidth + x] = map.value(atX: x, y: y)
                }
            }
            let shadowAlpha = ShadowRasterizer.shadowAlpha(
                coverage: coverage, width: canvasWidth, height: canvasHeight, offset: shadow.offset, blur: shadow.blur
            )
            let baseAlpha = shadow.color.alpha * state.alpha
            var data = [UInt8](repeating: 0, count: canvasWidth * canvasHeight * 4)
            for i in 0 ..< canvasWidth * canvasHeight {
                let a = shadowAlpha[i] * baseAlpha
                guard a > 0 else { continue }
                // Keep 255 as min's FIRST argument: an unvalidated out-of-range color
                // or alpha can make the product NaN/huge, and `min(255, nan)` returns
                // 255 (NaN compares false), so UInt8(...) never traps. Do not reorder.
                data[i * 4] = UInt8(max(0, min(255, shadow.color.red * a * 255)))
                data[i * 4 + 1] = UInt8(max(0, min(255, shadow.color.green * a * 255)))
                data[i * 4 + 2] = UInt8(max(0, min(255, shadow.color.blue * a * 255)))
                data[i * 4 + 3] = UInt8(max(0, min(255, a * 255)))
            }
            guard let shadowImage = try? Image(
                width: canvasWidth, height: canvasHeight, alphaInfo: .premultipliedLast, data: data
            ), let cgImage = createCGImage(from: shadowImage) else { return }
            // The shadow is already a finished device-space image, so draw it raw:
            // - Disable the native CG shadow set up for this op, or it would cast a
            //   shadow of the shadow.
            // - Reset alpha to 1 and the blend mode to normal: `state.alpha` is already
            //   baked into `baseAlpha`, so leaving the op's `setAlpha(state.alpha)`
            //   active would fade it twice (matching BitmapRenderer's single fade).
            // - Reset the CTM to draw at device pixels (the coverage was rasterized in
            //   device space). This assumes the caller's base CTM is the identity, the
            //   same 1:1 device mapping every PureDraw renderer assumes.
            // Then flip for CoreGraphics's bottom-left origin, like the drawImage path.
            targetContext.saveGState()
            targetContext.setShadow(offset: .zero, blur: 0, color: nil)
            targetContext.setAlpha(1)
            targetContext.setBlendMode(.normal)
            targetContext.concatenate(targetContext.ctm.inverted())
            targetContext.translateBy(x: 0, y: CGFloat(canvasHeight))
            targetContext.scaleBy(x: 1, y: -1)
            targetContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)))
            targetContext.restoreGState()
        }

        private func applyCTMAndMask(state: GraphicState, maskCache: inout [(source: Image, mask: CGImage)]) {
            let t = state.transform
            if let maskImage = state.maskImage,
               let maskRect = state.maskRect,
               let maskTransform = state.maskTransform,
               let cgMask = cachedMaskCGImage(for: maskImage, cache: &maskCache)
            {
                // AffineTransform builders append (self first, then step), unlike
                // their CoreGraphics namesakes which prepend: flip = scale, then
                // translate, mapping clip-space y' to maskRect.maxY - y'.
                let flip = Geometry.AffineTransform.identity
                    .scaledBy(x: 1.0, y: -1.0)
                    .translatedBy(x: maskRect.origin.x, y: maskRect.origin.y + maskRect.height)

                // Clip space -> user space (flip) -> device space (mask CTM).
                let clipCTM = flip.concatenating(maskTransform)
                targetContext.concatenate(CGAffineTransform(clipCTM))
                targetContext.clip(to: CGRect(x: 0, y: 0, width: CGFloat(maskRect.width), height: CGFloat(maskRect.height)), mask: cgMask)

                // Replace clipCTM with the drawing transform: t composed with
                // clipCTM's inverse, in that order.
                let remaining = t.concatenating(clipCTM.inverted())
                targetContext.concatenate(CGAffineTransform(remaining))
            } else {
                targetContext.concatenate(CGAffineTransform(t))
            }
        }

        /// Returns the DeviceGray mask for the image, converting at most once
        /// per render pass. Lookup is by `Image` equality, which short-circuits
        /// when both values share the same pixel storage.
        private func cachedMaskCGImage(for image: Image, cache: inout [(source: Image, mask: CGImage)]) -> CGImage? {
            if let hit = cache.first(where: { $0.source == image }) {
                return hit.mask
            }
            guard let converted = createMaskCGImage(from: image) else { return nil }
            cache.append((source: image, mask: converted))
            return converted
        }

        /// Builds the DeviceGray, no-alpha image that `CGContext.clip(to:mask:)` requires.
        /// Coverage matches `BitmapRenderer`: the mask's alpha channel when present, luminance otherwise.
        private func createMaskCGImage(from image: Image) -> CGImage? {
            var grayData = [UInt8]()
            grayData.reserveCapacity(image.width * image.height)
            for y in 0 ..< image.height {
                for x in 0 ..< image.width {
                    grayData.append(UInt8((image.maskCoverage(x: x, y: y) * 255.0).rounded()))
                }
            }
            guard let provider = CGDataProvider(data: Data(grayData) as CFData) else {
                return nil
            }
            return CGImage(
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: image.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }

        private func createCGImage(from image: Image) -> CGImage? {
            guard let provider = CGDataProvider(data: Data(image.data) as CFData) else {
                return nil
            }
            let cgColorSpace: CGColorSpace = switch image.colorSpace {
            case .deviceRGB:
                CGColorSpaceCreateDeviceRGB()
            case .deviceCMYK:
                CGColorSpaceCreateDeviceCMYK()
            case .deviceGray:
                CGColorSpaceCreateDeviceGray()
            }
            let cgAlphaInfo: CGImageAlphaInfo = switch image.alphaInfo {
            case .none: .none
            case .premultipliedLast: .premultipliedLast
            case .premultipliedFirst: .premultipliedFirst
            case .last: .last
            case .first: .first
            case .noneSkipLast: .noneSkipLast
            case .noneSkipFirst: .noneSkipFirst
            }
            let bitmapInfo = CGBitmapInfo(rawValue: cgAlphaInfo.rawValue)
            guard let cgImage = CGImage(
                width: image.width,
                height: image.height,
                bitsPerComponent: image.bitsPerComponent,
                bitsPerPixel: image.bitsPerPixel,
                bytesPerRow: image.bytesPerRow,
                space: cgColorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            ) else {
                return nil
            }

            if let maskingColors = image.maskingColors, !image.alphaInfo.hasAlpha {
                let maxVal = CGFloat((1 << image.bitsPerComponent) - 1)
                let cgMaskingColors = maskingColors.map { CGFloat($0) * maxVal }
                // copy(maskingColorComponents:) returns nil for unsupported layouts; draw unmasked rather than dropping the image.
                return cgImage.copy(maskingColorComponents: cgMaskingColors) ?? cgImage
            }

            return cgImage
        }

        private func applyFillColor(_ color: Color) {
            switch color.colorSpace {
            case .deviceRGB:
                targetContext.setFillColor(
                    red: CGFloat(color.components[0]),
                    green: CGFloat(color.components[1]),
                    blue: CGFloat(color.components[2]),
                    alpha: CGFloat(color.components[3])
                )
            case .deviceGray:
                let colorSpace = CGColorSpaceCreateDeviceGray()
                if let cgColor = CGColor(colorSpace: colorSpace, components: [CGFloat(color.components[0]), CGFloat(color.components[1])]) {
                    targetContext.setFillColor(cgColor)
                }
            case .deviceCMYK:
                let colorSpace = CGColorSpaceCreateDeviceCMYK()
                if let cgColor = CGColor(colorSpace: colorSpace, components: color.components.map { CGFloat($0) }) {
                    targetContext.setFillColor(cgColor)
                }
            }
        }

        private func applyStrokeColor(_ color: Color) {
            switch color.colorSpace {
            case .deviceRGB:
                targetContext.setStrokeColor(
                    red: CGFloat(color.components[0]),
                    green: CGFloat(color.components[1]),
                    blue: CGFloat(color.components[2]),
                    alpha: CGFloat(color.components[3])
                )
            case .deviceGray:
                let colorSpace = CGColorSpaceCreateDeviceGray()
                if let cgColor = CGColor(colorSpace: colorSpace, components: [CGFloat(color.components[0]), CGFloat(color.components[1])]) {
                    targetContext.setStrokeColor(cgColor)
                }
            case .deviceCMYK:
                let colorSpace = CGColorSpaceCreateDeviceCMYK()
                if let cgColor = CGColor(colorSpace: colorSpace, components: color.components.map { CGFloat($0) }) {
                    targetContext.setStrokeColor(cgColor)
                }
            }
        }

        private func createCGGradient(from gradient: Gradient) throws -> CGGradient {
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let cgColors = gradient.stops.map { stop in
                (CGColor(colorSpace: colorSpace, components: [
                    CGFloat(stop.color.red),
                    CGFloat(stop.color.green),
                    CGFloat(stop.color.blue),
                    CGFloat(stop.color.alpha),
                ]) ?? CGColor.black) as AnyObject
            }
            let locations = gradient.stops.map { CGFloat($0.location) }
            guard let cgGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: cgColors as CFArray,
                locations: locations
            ) else {
                throw RenderingError.cannotCreateGradient
            }
            return cgGradient
        }

        private func createCGPath(from path: Path) throws -> CGPath {
            let mutablePath = CGMutablePath()
            for element in path.elements {
                switch element {
                case let .move(to):
                    mutablePath.move(to: CGPoint(x: CGFloat(to.x), y: CGFloat(to.y)))
                case let .line(to):
                    mutablePath.addLine(to: CGPoint(x: CGFloat(to.x), y: CGFloat(to.y)))
                case let .quadCurve(to, control):
                    mutablePath.addQuadCurve(
                        to: CGPoint(x: CGFloat(to.x), y: CGFloat(to.y)),
                        control: CGPoint(x: CGFloat(control.x), y: CGFloat(control.y))
                    )
                case let .cubicCurve(to, control1, control2):
                    mutablePath.addCurve(
                        to: CGPoint(x: CGFloat(to.x), y: CGFloat(to.y)),
                        control1: CGPoint(x: CGFloat(control1.x), y: CGFloat(control1.y)),
                        control2: CGPoint(x: CGFloat(control2.x), y: CGFloat(control2.y))
                    )
                case .close:
                    mutablePath.closeSubpath()
                }
            }
            return mutablePath
        }
    }

    private extension CGLineCap {
        init(from cap: LineCap) {
            switch cap {
            case .butt: self = .butt
            case .round: self = .round
            case .square: self = .square
            }
        }
    }

    private extension CGLineJoin {
        init(from join: LineJoin) {
            switch join {
            case .miter: self = .miter
            case .round: self = .round
            case .bevel: self = .bevel
            }
        }
    }

    private extension CGBlendMode {
        init(from mode: BlendMode) {
            switch mode {
            case .normal: self = .normal
            case .multiply: self = .multiply
            case .screen: self = .screen
            case .overlay: self = .overlay
            case .darken: self = .darken
            case .lighten: self = .lighten
            case .colorDodge: self = .colorDodge
            case .colorBurn: self = .colorBurn
            case .softLight: self = .softLight
            case .hardLight: self = .hardLight
            case .difference: self = .difference
            case .exclusion: self = .exclusion
            case .hue: self = .hue
            case .saturation: self = .saturation
            case .color: self = .color
            case .luminosity: self = .luminosity
            case .clear: self = .clear
            case .copy: self = .copy
            case .sourceIn: self = .sourceIn
            case .sourceOut: self = .sourceOut
            case .sourceAtop: self = .sourceAtop
            case .destinationOver: self = .destinationOver
            case .destinationIn: self = .destinationIn
            case .destinationOut: self = .destinationOut
            case .destinationAtop: self = .destinationAtop
            case .xor: self = .xor
            case .plusDarker: self = .plusDarker
            case .plusLighter: self = .plusLighter
            }
        }
    }

    private extension CGInterpolationQuality {
        init(from quality: InterpolationQuality) {
            switch quality {
            case .default: self = .default
            case .none: self = .none
            case .low: self = .low
            case .medium: self = .medium
            case .high: self = .high
            }
        }
    }

    private extension CGAffineTransform {
        init(_ t: Geometry.AffineTransform) {
            self.init(
                a: CGFloat(t.a),
                b: CGFloat(t.b),
                c: CGFloat(t.c),
                d: CGFloat(t.d),
                tx: CGFloat(t.tx),
                ty: CGFloat(t.ty)
            )
        }
    }
#endif
