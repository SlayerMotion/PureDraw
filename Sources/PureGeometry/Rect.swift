//
//  Rect.swift
//  PureDraw
//

import Foundation
import PureValidation

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
        origin = Point(x: x, y: y)
        self.width = width
        self.height = height
    }

    public var minX: Double {
        origin.x
    }

    public var minY: Double {
        origin.y
    }

    public var maxX: Double {
        origin.x + width
    }

    public var maxY: Double {
        origin.y + height
    }

    public var midX: Double {
        origin.x + width / 2.0
    }

    public var midY: Double {
        origin.y + height / 2.0
    }

    public var isEmpty: Bool {
        width <= 0.0 || height <= 0.0
    }

    public func standardized() -> Rect {
        var r = self
        if r.width < 0 {
            r.origin.x += r.width
            r.width = -r.width
        }
        if r.height < 0 {
            r.origin.y += r.height
            r.height = -r.height
        }
        return r
    }

    public func integral() -> Rect {
        let std = standardized()
        let minX = floor(std.minX)
        let minY = floor(std.minY)
        let maxX = ceil(std.maxX)
        let maxY = ceil(std.maxY)
        return Rect(x: minX, y: minY, width: max(0.0, maxX - minX), height: max(0.0, maxY - minY))
    }

    public func insetBy(dx: Double, dy: Double) -> Rect {
        let std = standardized()
        return Rect(
            x: std.origin.x + dx,
            y: std.origin.y + dy,
            width: max(0.0, std.width - 2.0 * dx),
            height: max(0.0, std.height - 2.0 * dy),
        )
    }

    public func offsetBy(dx: Double, dy: Double) -> Rect {
        Rect(
            origin: Point(x: origin.x + dx, y: origin.y + dy),
            width: width,
            height: height,
        )
    }

    public func centered(in outer: Rect) -> Rect {
        let stdSelf = standardized()
        let stdOuter = outer.standardized()
        let newX = stdOuter.origin.x + floor((stdOuter.width - stdSelf.width) / 2.0)
        let newY = stdOuter.origin.y + floor((stdOuter.height - stdSelf.height) / 2.0)
        return Rect(x: newX, y: newY, width: stdSelf.width, height: stdSelf.height)
    }

    public func divided(at amount: Double, from edge: RectEdge) -> (slice: Rect, remainder: Rect) {
        let std = standardized()
        let sliceAmount = min(max(0.0, amount), (edge == .minX || edge == .maxX) ? std.width : std.height)

        switch edge {
        case .minX:
            let slice = Rect(x: std.minX, y: std.minY, width: sliceAmount, height: std.height)
            let remainder = Rect(x: std.minX + sliceAmount, y: std.minY, width: std.width - sliceAmount, height: std.height)
            return (slice, remainder)
        case .minY:
            let slice = Rect(x: std.minX, y: std.minY, width: std.width, height: sliceAmount)
            let remainder = Rect(x: std.minX, y: std.minY + sliceAmount, width: std.width, height: std.height - sliceAmount)
            return (slice, remainder)
        case .maxX:
            let slice = Rect(x: std.maxX - sliceAmount, y: std.minY, width: sliceAmount, height: std.height)
            let remainder = Rect(x: std.minX, y: std.minY, width: std.width - sliceAmount, height: std.height)
            return (slice, remainder)
        case .maxY:
            let slice = Rect(x: std.minX, y: std.maxY - sliceAmount, width: std.width, height: sliceAmount)
            let remainder = Rect(x: std.minX, y: std.minY, width: std.width, height: std.height - sliceAmount)
            return (slice, remainder)
        }
    }

    public func contains(_ point: Point) -> Bool {
        let std = standardized()
        return point.x >= std.minX && point.x <= std.maxX &&
            point.y >= std.minY && point.y <= std.maxY
    }

    public func contains(_ other: Rect) -> Bool {
        let std = standardized()
        let stdOther = other.standardized()
        return stdOther.minX >= std.minX && stdOther.maxX <= std.maxX &&
            stdOther.minY >= std.minY && stdOther.maxY <= std.maxY
    }

    public func intersects(_ other: Rect) -> Bool {
        let std = standardized()
        let stdOther = other.standardized()
        return std.minX < stdOther.maxX && stdOther.minX < std.maxX &&
            std.minY < stdOther.maxY && stdOther.minY < std.maxY
    }

    public func union(_ other: Rect) -> Rect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let std = standardized()
        let stdOther = other.standardized()
        let minX = min(std.minX, stdOther.minX)
        let minY = min(std.minY, stdOther.minY)
        let maxX = max(std.maxX, stdOther.maxX)
        let maxY = max(std.maxY, stdOther.maxY)
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func intersection(_ other: Rect) -> Rect {
        let std = standardized()
        let stdOther = other.standardized()
        let minX = max(std.minX, stdOther.minX)
        let minY = max(std.minY, stdOther.minY)
        let maxX = min(std.maxX, stdOther.maxX)
        let maxY = min(std.maxY, stdOther.maxY)
        if minX < maxX, minY < maxY {
            return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            return .zero
        }
    }

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

    public static var defaultValidator: Validator<Rect> {
        Validator()
            .validating(.rectHasValidDimensions)
            .validating(.rectIsFinite)
    }
}
