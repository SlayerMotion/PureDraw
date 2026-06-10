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

        public init(context: CGContext) {
            targetContext = context
        }

        public func render(_ context: GraphicsContext) throws {
            for operation in context.commands {
                switch operation.kind {
                case .beginTransparencyLayer:
                    targetContext.saveGState()

                    // Apply CTM & Mask
                    applyCTMAndMask(state: operation.state)
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
                    applyCTMAndMask(state: operation.state)
                    targetContext.setAlpha(CGFloat(operation.state.alpha))
                    targetContext.setBlendMode(CGBlendMode(from: operation.state.blendMode))

                    // 3. Apply Style Parameters
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

                    case .beginTransparencyLayer, .endTransparencyLayer:
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

        private func applyCTMAndMask(state: GraphicState) {
            let t = state.transform
            if let maskImage = state.maskImage,
               let maskRect = state.maskRect,
               let maskTransform = state.maskTransform,
               let cgMask = createCGImage(from: maskImage)
            {
                let flip = Geometry.AffineTransform.identity
                    .translatedBy(x: maskRect.origin.x, y: maskRect.origin.y + maskRect.height)
                    .scaledBy(x: 1.0, y: -1.0)

                let clipCTM = maskTransform.concatenating(flip)
                targetContext.concatenate(CGAffineTransform(clipCTM))
                targetContext.clip(to: CGRect(x: 0, y: 0, width: CGFloat(maskRect.width), height: CGFloat(maskRect.height)), mask: cgMask)

                let remaining = clipCTM.inverted().concatenating(t)
                targetContext.concatenate(CGAffineTransform(remaining))
            } else {
                targetContext.concatenate(CGAffineTransform(t))
            }
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

            if let maskingColors = image.maskingColors {
                let maxVal = CGFloat((1 << image.bitsPerComponent) - 1)
                let cgMaskingColors = maskingColors.map { CGFloat($0) * maxVal }
                return cgImage.copy(maskingColorComponents: cgMaskingColors)
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
