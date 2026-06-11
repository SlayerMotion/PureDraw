//
//  ProjectiveImageRasterizer.swift
//  PureDraw
//

import Core
import Foundation
import Geometry

/// The shared software texture-mapper: warps an image's placement rectangle onto a
/// device-space quad through a `ProjectiveTransform`, inverse-mapping each output
/// pixel and sampling the source. Both `BitmapRenderer` and `CoreGraphicsRenderer`
/// use it so a perspective image draw renders the same picture (CoreGraphics has no
/// native projective image draw). This is what lets a layer flattened to a texture
/// be mapped onto its 3D-projected quad.
enum ProjectiveImageRasterizer {
    /// A premultiplied-RGBA device buffer (`width` x `height`) with `image` mapped
    /// from `rect` through `transform`, transparent everywhere the quad does not
    /// cover. Returns `nil` if the transform is singular or the quad is off-canvas.
    static func warp(
        _ image: Image,
        in rect: Rect,
        transform: ProjectiveTransform,
        width: Int,
        height: Int,
        quality: InterpolationQuality,
        antialiased: Bool
    ) -> [UInt8]? {
        // A singular transform has no inverse to map device pixels back through, so
        // it cannot be rasterized.
        guard width > 0, height > 0, rect.width > 0, rect.height > 0, transform.determinant != 0 else { return nil }

        let corners = [
            Point(x: rect.minX, y: rect.minY), Point(x: rect.maxX, y: rect.minY),
            Point(x: rect.maxX, y: rect.maxY), Point(x: rect.minX, y: rect.maxY),
        ].map { $0.applying(transform) }
        guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }

        let minX = max(0, Int(floor(corners.map(\.x).min() ?? 0)))
        let maxX = min(width - 1, Int(ceil(corners.map(\.x).max() ?? 0)))
        let minY = max(0, Int(floor(corners.map(\.y).min() ?? 0)))
        let maxY = min(height - 1, Int(ceil(corners.map(\.y).max() ?? 0)))
        guard minX <= maxX, minY <= maxY else { return nil }

        // The rect center always projects to the front (inside the quad); a sample
        // whose homogeneous w has the opposite sign is behind the projection plane
        // and must be rejected, or a quad straddling the horizon paints a mirrored
        // ghost. (`w = m13·x + m23·y + m33`, matching `Point.applying`.)
        let centerW = transform.m13 * (rect.minX + rect.width / 2)
            + transform.m23 * (rect.minY + rect.height / 2) + transform.m33
        let frontIsPositive = centerW > 0

        let inverse = transform.inverted()
        // Antialiasing is subpixel coverage sampling, the way Quartz rasterizes (a
        // pixel's contribution is the fraction of its area inside the quad, not the
        // naive "touch any part" rule). Sample an N x N grid of subpixel positions per
        // device pixel; uncovered samples contribute zero, so the premultiplied
        // average is coverage-weighted and the quad edges fade smoothly. N = 1
        // (`!antialiased`) is a single centered sample, exact for an axis-aligned quad.
        let samplesPerAxis = antialiased ? 4 : 1
        let sampleCount = Double(samplesPerAxis * samplesPerAxis)
        let step = 1.0 / Double(samplesPerAxis)

        var output = [UInt8](repeating: 0, count: width * height * 4)
        for y in minY ... maxY {
            for x in minX ... maxX {
                var sumRed = 0.0, sumGreen = 0.0, sumBlue = 0.0, sumAlpha = 0.0
                for subY in 0 ..< samplesPerAxis {
                    for subX in 0 ..< samplesPerAxis {
                        let deviceX = Double(x) + (Double(subX) + 0.5) * step
                        let deviceY = Double(y) + (Double(subY) + 0.5) * step
                        let userPoint = Point(x: deviceX, y: deviceY).applying(inverse)
                        guard userPoint.x.isFinite, userPoint.y.isFinite else { continue }
                        let pointW = transform.m13 * userPoint.x + transform.m23 * userPoint.y + transform.m33
                        guard pointW != 0, (pointW > 0) == frontIsPositive, rect.contains(userPoint) else { continue }
                        let u = (userPoint.x - rect.minX) / rect.width
                        let v = (userPoint.y - rect.minY) / rect.height
                        let color = image.sampledColor(u: u, v: v, quality: quality)
                        let alpha = color.alpha
                        guard alpha > 0 else { continue }
                        sumRed += color.red * alpha
                        sumGreen += color.green * alpha
                        sumBlue += color.blue * alpha
                        sumAlpha += alpha
                    }
                }
                guard sumAlpha > 0 else { continue }
                let index = (y * width + x) * 4
                output[index] = UInt8(max(0, min(255, sumRed / sampleCount * 255)))
                output[index + 1] = UInt8(max(0, min(255, sumGreen / sampleCount * 255)))
                output[index + 2] = UInt8(max(0, min(255, sumBlue / sampleCount * 255)))
                output[index + 3] = UInt8(max(0, min(255, sumAlpha / sampleCount * 255)))
            }
        }
        return output
    }
}
