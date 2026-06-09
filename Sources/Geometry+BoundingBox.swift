//
//  Geometry+BoundingBox.swift
//  PureDraw
//

import Foundation

extension Path {
    /// Calculates the exact mathematical bounding box of the entire path.
    ///
    /// Unlike a naive bounding box that just checks control points, this method calculates 
    /// the first derivative of the Bézier curves to find the true extrema (min/max points) 
    /// where the curve direction changes.
    public var boundingBox: Rect {
        guard !elements.isEmpty else { return .zero }
        
        var minX: Double = .infinity
        var minY: Double = .infinity
        var maxX: Double = -.infinity
        var maxY: Double = -.infinity
        
        var currentPoint = Point.zero
        
        func updateBounds(with p: Point) {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        
        for element in elements {
            switch element {
            case .move(let to):
                currentPoint = to
                updateBounds(with: to)
                
            case .line(let to):
                updateBounds(with: to)
                currentPoint = to
                
            case .quadCurve(let to, let control):
                let extremaX = quadraticExtrema(p0: currentPoint.x, p1: control.x, p2: to.x)
                let extremaY = quadraticExtrema(p0: currentPoint.y, p1: control.y, p2: to.y)
                
                for t in extremaX {
                    updateBounds(with: Point(
                        x: evaluateQuadratic(t: t, p0: currentPoint.x, p1: control.x, p2: to.x),
                        y: evaluateQuadratic(t: t, p0: currentPoint.y, p1: control.y, p2: to.y)
                    ))
                }
                for t in extremaY {
                    updateBounds(with: Point(
                        x: evaluateQuadratic(t: t, p0: currentPoint.x, p1: control.x, p2: to.x),
                        y: evaluateQuadratic(t: t, p0: currentPoint.y, p1: control.y, p2: to.y)
                    ))
                }
                updateBounds(with: to)
                currentPoint = to
                
            case .cubicCurve(let to, let control1, let control2):
                let extremaX = cubicExtrema(p0: currentPoint.x, p1: control1.x, p2: control2.x, p3: to.x)
                let extremaY = cubicExtrema(p0: currentPoint.y, p1: control1.y, p2: control2.y, p3: to.y)
                
                for t in extremaX {
                    updateBounds(with: Point(
                        x: evaluateCubic(t: t, p0: currentPoint.x, p1: control1.x, p2: control2.x, p3: to.x),
                        y: evaluateCubic(t: t, p0: currentPoint.y, p1: control1.y, p2: control2.y, p3: to.y)
                    ))
                }
                for t in extremaY {
                    updateBounds(with: Point(
                        x: evaluateCubic(t: t, p0: currentPoint.x, p1: control1.x, p2: control2.x, p3: to.x),
                        y: evaluateCubic(t: t, p0: currentPoint.y, p1: control1.y, p2: control2.y, p3: to.y)
                    ))
                }
                updateBounds(with: to)
                currentPoint = to
                
            case .close:
                break // Close just draws a line back, which doesn't exceed existing bounds.
            }
        }
        
        if minX == .infinity { return .zero }
        
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    // MARK: - Mathematical Helpers
    
    /// Evaluates a 1D quadratic Bézier curve at time \`t\` (0...1).
    private func evaluateQuadratic(t: Double, p0: Double, p1: Double, p2: Double) -> Double {
        let mt = 1.0 - t
        return (mt * mt * p0) + (2.0 * mt * t * p1) + (t * t * p2)
    }
    
    /// Evaluates a 1D cubic Bézier curve at time \`t\` (0...1).
    private func evaluateCubic(t: Double, p0: Double, p1: Double, p2: Double, p3: Double) -> Double {
        let mt = 1.0 - t
        let mt2 = mt * mt
        let mt3 = mt2 * mt
        let t2 = t * t
        let t3 = t2 * t
        
        return (mt3 * p0) + (3.0 * mt2 * t * p1) + (3.0 * mt * t2 * p2) + (t3 * p3)
    }
    
    /// Finds the \`t\` values (0...1) where the first derivative of the quadratic curve is zero.
    private func quadraticExtrema(p0: Double, p1: Double, p2: Double) -> [Double] {
        // Derivative of quadratic: 2(1-t)(p1-p0) + 2t(p2-p1) = 0
        // Solves to: t = (p0 - p1) / (p0 - 2p1 + p2)
        let divisor = p0 - 2.0 * p1 + p2
        if divisor == 0 { return [] }
        
        let t = (p0 - p1) / divisor
        if t > 0.0 && t < 1.0 {
            return [t]
        }
        return []
    }
    
    /// Finds the \`t\` values (0...1) where the first derivative of the cubic curve is zero.
    private func cubicExtrema(p0: Double, p1: Double, p2: Double, p3: Double) -> [Double] {
        // Derivative of cubic is a quadratic equation: At^2 + Bt + C = 0
        let a = 3.0 * (-p0 + 3.0 * p1 - 3.0 * p2 + p3)
        let b = 6.0 * (p0 - 2.0 * p1 + p2)
        let c = 3.0 * (p1 - p0)
        
        if a == 0 {
            if b == 0 { return [] }
            let t = -c / b
            return (t > 0.0 && t < 1.0) ? [t] : []
        }
        
        let discriminant = (b * b) - (4.0 * a * c)
        if discriminant < 0 { return [] } // No real roots
        
        let sqrtD = sqrt(discriminant)
        let t1 = (-b + sqrtD) / (2.0 * a)
        let t2 = (-b - sqrtD) / (2.0 * a)
        
        var roots: [Double] = []
        if t1 > 0.0 && t1 < 1.0 { roots.append(t1) }
        if t2 > 0.0 && t2 < 1.0 { roots.append(t2) }
        
        return roots
    }
}
