import Foundation
import Geometry
import Validation

/// A non-linear swirl (twirl) field: rotates points around a center by an angle that is full at the center
/// and tapers linearly to zero at the radius. Points outside the radius are untouched. This is the forward
/// point map of our own `PureImage.TwirlDistortion` (which mirrors `CITwirlDistortion`): the same
/// `falloff = 1 - distance / radius` convention and the same distance-preserving rotation, expressed
/// forward so it can deform a vector path directly instead of sampling pixels.
public struct SwirlDeformer: Sendable {
    /// The center of the swirl.
    public var center: Point

    /// The radius of influence. Points beyond this distance are unchanged.
    public var radius: Double

    /// The maximum rotation, in radians, applied at the center.
    public var angle: Double

    /// Creates a swirl rotating up to `angle` radians at `center`, fading out by `radius`.
    public init(center: Point, radius: Double, angle: Double = .pi) {
        self.center = center
        self.radius = radius
        self.angle = angle
    }

    /// Rotates the point around the center by `angle * (1 - distance / radius)`, preserving its distance.
    public func transform(_ point: Point) -> Point {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        guard radius > 0, dist < radius else { return point }

        let theta = angle * (1 - dist / radius)
        let cosTheta = cos(theta)
        let sinTheta = sin(theta)
        return Point(
            x: center.x + dx * cosTheta - dy * sinTheta,
            y: center.y + dx * sinTheta + dy * cosTheta
        )
    }
}

public extension Validation {
    /// A `SwirlDeformer`'s values are finite; a NaN or infinite field produces un-renderable points.
    static var swirlDeformerValuesAreFinite: Validation<Document, SwirlDeformer> {
        .init(description: "SwirlDeformer center, radius, and angle are finite", check: { context in
            let deformer = context.subject
            return deformer.center.x.isFinite && deformer.center.y.isFinite
                && deformer.radius.isFinite && deformer.angle.isFinite
        })
    }
}

extension SwirlDeformer: Validatable {
    /// Validates that the center, radius, and angle are finite.
    public static var defaultValidator: Validator<SwirlDeformer> {
        Validator().validating(.swirlDeformerValuesAreFinite)
    }
}
