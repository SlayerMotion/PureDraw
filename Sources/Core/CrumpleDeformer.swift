import Foundation
import Geometry
import Validation

/// A non-linear deformation field that simulates paper being crumpled or squashed by a hand.
///
/// It combines a radial "pinch" (pulling points towards a center coordinates) with a
/// multi-octave pseudo-random wrinkling displacement based on sine and cosine waves.
public struct CrumpleDeformer: Sendable {
    /// The center of the hand pinch/squash.
    public var center: Point

    /// The radius of influence of the pinch.
    public var radius: Double

    /// The strength of the pinch pulling points toward the center (e.g. 0.0 to 0.8).
    public var pinchStrength: Double

    /// The scale of the wrinkles (multiplier on wrinkle amplitude).
    public var wrinkleStrength: Double

    /// Creates a deformer pinching toward `center` within `radius`, with the given pinch and
    /// wrinkle strengths.
    public init(
        center: Point,
        radius: Double,
        pinchStrength: Double = 0.35,
        wrinkleStrength: Double = 1.0
    ) {
        self.center = center
        self.radius = radius
        self.pinchStrength = pinchStrength
        self.wrinkleStrength = wrinkleStrength
    }

    /// Transforms a point by applying the pinch and wrinkling displacement.
    public func transform(_ point: Point) -> Point {
        // 1. Calculate distance and vector to pinch center
        let dxCenter = center.x - point.x
        let dyCenter = center.y - point.y
        let dist = sqrt(dxCenter * dxCenter + dyCenter * dyCenter)

        // 2. Apply pinch (points pulled inwards towards center, stronger closer to the center)
        var pinchedPoint = point
        if dist > 0.1 {
            let pinchFactor = pinchStrength * exp(-dist / radius)
            pinchedPoint.x += dxCenter * pinchFactor
            pinchedPoint.y += dyCenter * pinchFactor
        }

        // 3. Apply high-frequency creases/wrinkles using multi-octave sine waves at different angles
        var wx = 0.0
        var wy = 0.0

        let octaves = [
            (freq: 0.02, amp: 10.0, angle: 0.25),
            (freq: 0.06, amp: 4.5, angle: 1.20),
            (freq: 0.15, amp: 1.8, angle: -0.65),
            (freq: 0.35, amp: 0.6, angle: 2.10),
        ]

        for octave in octaves {
            let cosA = cos(octave.angle)
            let sinA = sin(octave.angle)
            let rx = pinchedPoint.x * cosA - pinchedPoint.y * sinA
            let ry = pinchedPoint.x * sinA + pinchedPoint.y * cosA

            wx += sin(rx * octave.freq) * octave.amp
            wy += cos(ry * octave.freq) * octave.amp
        }

        let finalX = pinchedPoint.x + wx * wrinkleStrength
        let finalY = pinchedPoint.y + wy * wrinkleStrength

        return Point(x: finalX, y: finalY)
    }
}

public extension Validation {
    /// A `CrumpleDeformer`'s center, radius, and strengths are finite. The transform
    /// tolerates any finite values (a zero or negative radius simply disables or
    /// inverts the pinch), but a NaN or infinite field produces an un-renderable
    /// point, so finiteness is the genuine invariant.
    static var crumpleDeformerValuesAreFinite: Validation<Document, CrumpleDeformer> {
        .init(description: "CrumpleDeformer center, radius, and strengths are finite", check: { context in
            let deformer = context.subject
            return deformer.center.x.isFinite && deformer.center.y.isFinite
                && deformer.radius.isFinite
                && deformer.pinchStrength.isFinite && deformer.wrinkleStrength.isFinite
        })
    }
}

extension CrumpleDeformer: Validatable {
    public static var defaultValidator: Validator<CrumpleDeformer> {
        Validator().validating(.crumpleDeformerValuesAreFinite)
    }
}
