import Foundation
import Geometry
import Validation

/// A non-linear shrivel field: the sheet contracts toward its center, more at the edges than the middle,
/// with wrinkles running around it, the way fruit or paper shrinks and puckers as it dries. A forward
/// point map so it can shrivel a vector path directly.
public struct ShrivelDeformer: Sendable {
    /// The center the sheet shrinks toward.
    public var center: Point

    /// The radius of influence; the contraction is measured against this extent.
    public var radius: Double

    /// How much the outer points pull inward, 0 (none) to about 0.8 (strong shrivel).
    public var shrink: Double

    /// The amplitude of the wrinkles that run around the shrinking sheet.
    public var wrinkle: Double

    /// Creates a shrivel contracting toward `center` within `radius`.
    public init(center: Point, radius: Double, shrink: Double = 0.4, wrinkle: Double = 1.0) {
        self.center = center
        self.radius = radius
        self.shrink = shrink
        self.wrinkle = wrinkle
    }

    /// Pulls the point toward the center by an amount that grows with distance, and adds an angular ripple.
    public func transform(_ point: Point) -> Point {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0.0001, radius > 0 else { return point }

        let t = min(dist / radius, 1)
        let contract = 1 - shrink * t
        let ripple = wrinkle * radius * 0.04 * sin(atan2(dy, dx) * 9) * t
        let newDist = dist * contract + ripple
        let scale = newDist / dist
        return Point(x: center.x + dx * scale, y: center.y + dy * scale)
    }
}

public extension Validation {
    /// A `ShrivelDeformer`'s values are finite; a NaN or infinite field produces un-renderable points.
    static var shrivelDeformerValuesAreFinite: Validation<Document, ShrivelDeformer> {
        .init(description: "ShrivelDeformer center, radius, shrink, and wrinkle are finite", check: { context in
            let deformer = context.subject
            return deformer.center.x.isFinite && deformer.center.y.isFinite
                && deformer.radius.isFinite && deformer.shrink.isFinite && deformer.wrinkle.isFinite
        })
    }
}

extension ShrivelDeformer: Validatable {
    /// Validates that the center, radius, shrink, and wrinkle are finite.
    public static var defaultValidator: Validator<ShrivelDeformer> {
        Validator().validating(.shrivelDeformerValuesAreFinite)
    }
}
