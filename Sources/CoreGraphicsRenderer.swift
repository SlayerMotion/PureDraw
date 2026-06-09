//
//  CoreGraphicsRenderer.swift
//  PureDraw
//

#if canImport(CoreGraphics)
import CoreGraphics

/// A renderer that executes the PureDraw command buffer on an Apple `CGContext`.
public struct CoreGraphicsRenderer: Renderer, @unchecked Sendable {
    public typealias Output = Void
    
    /// The target native CoreGraphics context.
    public let targetContext: CGContext
    
    public init(context: CGContext) {
        self.targetContext = context
    }
    
    public func render(_ context: GraphicsContext) throws {
        for operation in context.commands {
            // 1. Push Graphics State
            targetContext.saveGState()
            
            // 2. Apply CTM & Opacity
            let t = operation.state.transform
            targetContext.concatenate(CGAffineTransform(
                a: CGFloat(t.a),
                b: CGFloat(t.b),
                c: CGFloat(t.c),
                d: CGFloat(t.d),
                tx: CGFloat(t.tx),
                ty: CGFloat(t.ty)
            ))
            targetContext.setAlpha(CGFloat(operation.state.alpha))
            
            // 3. Apply Style Parameters
            targetContext.setLineWidth(CGFloat(operation.state.lineWidth))
            targetContext.setLineCap(CGLineCap(from: operation.state.lineCap))
            targetContext.setLineJoin(CGLineJoin(from: operation.state.lineJoin))
            targetContext.setMiterLimit(CGFloat(operation.state.miterLimit))
            
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
                    CGFloat(shadow.color.alpha)
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
            case .fill(let path, let rule):
                let cgPath = try createCGPath(from: path)
                targetContext.addPath(cgPath)
                let cgFillRule = (rule == .evenOdd) ? CGPathFillRule.evenOdd : CGPathFillRule.winding
                
                let fillCol = operation.state.fillColor
                targetContext.setFillColor(
                    red: CGFloat(fillCol.red),
                    green: CGFloat(fillCol.green),
                    blue: CGFloat(fillCol.blue),
                    alpha: CGFloat(fillCol.alpha)
                )
                targetContext.fillPath(using: cgFillRule)
                
            case .stroke(let path):
                let cgPath = try createCGPath(from: path)
                targetContext.addPath(cgPath)
                
                let strokeCol = operation.state.strokeColor
                targetContext.setStrokeColor(
                    red: CGFloat(strokeCol.red),
                    green: CGFloat(strokeCol.green),
                    blue: CGFloat(strokeCol.blue),
                    alpha: CGFloat(strokeCol.alpha)
                )
                targetContext.strokePath()
                
            case .drawLinearGradient(let grad, let start, let end, let options):
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
                
            case .drawRadialGradient(let grad, let startCenter, let startRadius, let endCenter, let endRadius, let options):
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
            }
            
            // 6. Pop Graphics State
            targetContext.restoreGState()
        }
    }
    
    private enum RenderingError: Error {
        case cannotCreateColorSpace
        case cannotCreateGradient
    }
    
    private func createCGGradient(from gradient: Gradient) throws -> CGGradient {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let cgColors = gradient.stops.map { stop in
            CGColor(colorSpace: colorSpace, components: [
                CGFloat(stop.color.red),
                CGFloat(stop.color.green),
                CGFloat(stop.color.blue),
                CGFloat(stop.color.alpha)
            ])! as AnyObject
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
            case .move(let to):
                mutablePath.move(to: CGPoint(x: CGFloat(to.x), y: CGFloat(to.y)))
            case .line(let to):
                mutablePath.addLine(to: CGPoint(x: CGFloat(to.x), y: CGFloat(to.y)))
            case .quadCurve(let to, let control):
                mutablePath.addQuadCurve(
                    to: CGPoint(x: CGFloat(to.x), y: CGFloat(to.y)),
                    control: CGPoint(x: CGFloat(control.x), y: CGFloat(control.y))
                )
            case .cubicCurve(let to, let control1, let control2):
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
#endif
