import Foundation
import Geometry
import Validation

/// A non-linear pinch field, the forward point map of Photoshop's Pinch and Spherize: every point keeps its
/// ray from the center but its distance is remapped along a power curve. A positive `amount` sucks points
/// inward (pinch), a negative one pushes them outward (bloat / spherize). Full at the center, fading to none
/// at the radius; points beyond the radius are untouched. Expressed forward so it can deform a vector path
/// directly instead of sampling pixels.
public struct PinchDeformer: Sendable {
    /// The center the field pinches toward or bloats away from.
    public var center: Point

    /// The radius of influence. Points beyond this distance are unchanged.
    public var radius: Double

    /// The strength: positive pinches inward, negative bloats outward. Constrained to greater than -1 so the
    /// power exponent stays positive; a sensible range is about -0.9 to 0.9.
    public var amount: Double

    /// Creates a pinch (positive `amount`) or bloat (negative) toward `center`, fading out by `radius`.
    public init(center: Point, radius: Double, amount: Double = 0.5) {
        self.center = center
        self.radius = radius
        self.amount = amount
    }

    /// Remaps the point's normalized distance `u` in `[0, 1]` to `u^(1 + amount)`, then eases that remap in
    /// by distance so the field blends smoothly to the identity at the radius. Distance from the center is
    /// rescaled; the angle is preserved, so the point stays on its own ray.
    public func transform(_ point: Point) -> Point {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        guard radius > 0, dist > 0.0001, dist < radius, amount > -1 else { return point }

        let u = dist / radius
        let remapped = pow(u, 1 + amount)
        // Ease the remap in by distance (full at the center, none at the rim) so the rim stays continuous.
        let blend = 1 - u
        let newU = u + (remapped - u) * blend
        let scale = newU / u
        return Point(x: center.x + dx * scale, y: center.y + dy * scale)
    }
}

public extension Validation {
    /// A `PinchDeformer`'s values are finite; a NaN or infinite field produces un-renderable points.
    static var pinchDeformerValuesAreFinite: Validation<Document, PinchDeformer> {
        .init(description: "PinchDeformer center, radius, and amount are finite", check: { context in
            let deformer = context.subject
            return deformer.center.x.isFinite && deformer.center.y.isFinite
                && deformer.radius.isFinite && deformer.amount.isFinite
        })
    }
}

extension PinchDeformer: Validatable {
    /// Validates that the center, radius, and amount are finite.
    public static var defaultValidator: Validator<PinchDeformer> {
        Validator().validating(.pinchDeformerValuesAreFinite)
    }
}
