import Foundation
import Geometry
import Validation

/// A non-linear ripple field, the forward point map of Photoshop's ZigZag "Pond Ripples": concentric waves
/// radiate from the center, the way paint or water moves when a finger is dipped in the middle. Each point
/// keeps its ray from the center and its distance is pushed out and pulled in by a sine of that distance,
/// fading to none at the radius. Expressed forward so it can deform a vector path directly.
public struct RippleDeformer: Sendable {
    /// The center the ripples radiate from.
    public var center: Point

    /// The radius of influence. Points beyond this distance are unchanged and the waves fade to it.
    public var radius: Double

    /// The peak displacement of a wave, as a fraction of the radius (so the field scales with its extent).
    public var amplitude: Double

    /// How many wave crests fall between the center and the radius.
    public var waves: Double

    /// Creates pond ripples radiating from `center`, fading out by `radius`.
    public init(center: Point, radius: Double, amplitude: Double = 0.08, waves: Double = 4) {
        self.center = center
        self.radius = radius
        self.amplitude = amplitude
        self.waves = waves
    }

    /// Displaces the point along its ray by `amplitude * radius * sin(2 pi * waves * u)`, eased out by a
    /// `1 - u` falloff so the rim stays put. The angle is preserved; only the radial distance ripples.
    public func transform(_ point: Point) -> Point {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        guard radius > 0, dist > 0.0001, dist < radius else { return point }

        let u = dist / radius
        let falloff = 1 - u
        let displacement = amplitude * radius * sin(2 * .pi * waves * u) * falloff
        let newDist = dist + displacement
        let scale = newDist / dist
        return Point(x: center.x + dx * scale, y: center.y + dy * scale)
    }
}

public extension Validation {
    /// A `RippleDeformer`'s values are finite; a NaN or infinite field produces un-renderable points.
    static var rippleDeformerValuesAreFinite: Validation<Document, RippleDeformer> {
        .init(description: "RippleDeformer center, radius, amplitude, and waves are finite", check: { context in
            let deformer = context.subject
            return deformer.center.x.isFinite && deformer.center.y.isFinite
                && deformer.radius.isFinite && deformer.amplitude.isFinite && deformer.waves.isFinite
        })
    }
}

extension RippleDeformer: Validatable {
    /// Validates that the center, radius, amplitude, and waves are finite.
    public static var defaultValidator: Validator<RippleDeformer> {
        Validator().validating(.rippleDeformerValuesAreFinite)
    }
}
