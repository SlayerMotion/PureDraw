import Foundation
import Geometry
import Validation

/// A non-linear page-curl field: the part of the sheet to the right of a curl line wraps forward around a
/// cylinder, lifting and rolling back like a turning page. A forward point map (the same effect family as
/// Core Image's `CIPageCurlTransition`) so it can curl a vector path directly.
public struct PageCurlDeformer: Sendable {
    /// The center of the sheet; `center.x` anchors where the curl line sweeps from.
    public var center: Point

    /// The half-extent of the sheet the curl line sweeps across.
    public var radius: Double

    /// How much of the sheet curls, 0 (none, line at the right edge) to 1 (all, line at the left edge).
    public var curl: Double

    /// The cylinder radius as a fraction of `radius`; smaller is a tighter roll.
    public var tightness: Double

    /// Creates a page curl rolling the right portion of the sheet forward.
    public init(center: Point, radius: Double, curl: Double = 0.5, tightness: Double = 0.25) {
        self.center = center
        self.radius = radius
        self.curl = curl
        self.tightness = tightness
    }

    /// Wraps points past the curl line onto a cylinder: x compresses by sine, y lifts by one minus cosine.
    public func transform(_ point: Point) -> Point {
        guard radius > 0 else { return point }
        let axisX = center.x + radius - (curl * 2 * radius)
        guard point.x > axisX else { return point }

        let cylinder = max(0.0001, tightness * radius)
        let arc = point.x - axisX
        let theta = min(arc / cylinder, .pi)
        return Point(
            x: axisX + cylinder * sin(theta),
            y: point.y - cylinder * (1 - cos(theta))
        )
    }
}

public extension Validation {
    /// A `PageCurlDeformer`'s values are finite; a NaN or infinite field produces un-renderable points.
    static var pageCurlDeformerValuesAreFinite: Validation<Document, PageCurlDeformer> {
        .init(description: "PageCurlDeformer center, radius, curl, and tightness are finite", check: { context in
            let deformer = context.subject
            return deformer.center.x.isFinite && deformer.center.y.isFinite
                && deformer.radius.isFinite && deformer.curl.isFinite && deformer.tightness.isFinite
        })
    }
}

extension PageCurlDeformer: Validatable {
    /// Validates that the center, radius, curl, and tightness are finite.
    public static var defaultValidator: Validator<PageCurlDeformer> {
        Validator().validating(.pageCurlDeformerValuesAreFinite)
    }
}
