//
//  Rect.swift
//  PureDraw
//

/// A rectangle in a two-dimensional coordinate system.
public struct Rect: Equatable, Sendable, Validatable {
    public var origin: Point
    public var width: Double
    public var height: Double
    
    public static let zero = Rect(origin: Point.zero, width: 0, height: 0)
    
    public init(origin: Point, width: Double, height: Double) {
        self.origin = origin
        self.width = width
        self.height = height
    }
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = Point(x: x, y: y)
        self.width = width
        self.height = height
    }
    
    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + width }
    public var maxY: Double { origin.y + height }
    
    /// Returns the smallest rectangle that contains the original rectangle after the transformation is applied.
    public func applying(_ t: AffineTransform) -> Rect {
        let p1 = Point(x: minX, y: minY).applying(t)
        let p2 = Point(x: maxX, y: minY).applying(t)
        let p3 = Point(x: minX, y: maxY).applying(t)
        let p4 = Point(x: maxX, y: maxY).applying(t)
        
        let minX = min(p1.x, p2.x, p3.x, p4.x)
        let maxX = max(p1.x, p2.x, p3.x, p4.x)
        let minY = min(p1.y, p2.y, p3.y, p4.y)
        let maxY = max(p1.y, p2.y, p3.y, p4.y)
        
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
