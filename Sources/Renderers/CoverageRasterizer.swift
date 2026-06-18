//
//  CoverageRasterizer.swift
//  PureDraw
//

import Core
import Foundation
import Geometry

/// Rasterizes filled paths into per-pixel coverage with a scanline pass.
///
/// Anti-aliased coverage samples several rows per pixel and accumulates
/// fractional horizontal overlap; aliased coverage tests pixel centers,
/// matching the previous per-pixel containment behavior.
struct CoverageRasterizer {
    let canvasWidth: Int
    let canvasHeight: Int

    /// Per-pixel coverage of a filled shape over a bounded region of the canvas.
    struct CoverageMap {
        let minX: Int
        let minY: Int
        let width: Int
        let height: Int
        let values: [Double]

        /// Coverage at device pixel `(x, y)`; zero outside the map's bounds.
        func value(atX x: Int, y: Int) -> Double {
            let localX = x - minX
            let localY = y - minY
            guard localX >= 0, localX < width, localY >= 0, localY < height else { return 0.0 }
            return values[localY * width + localX]
        }
    }

    private struct Edge {
        let x1, y1, x2, y2: Double
        let direction: Double
    }

    private static let subsampleRows = 4

    func coverage(of path: Path, rule: FillRule, antialiased: Bool) -> CoverageMap? {
        var edges: [Edge] = []
        var minXD = Double.infinity
        var maxXD = -Double.infinity
        var minYD = Double.infinity
        var maxYD = -Double.infinity

        for polygon in path.toPolygons() {
            guard polygon.count >= 2 else { continue }
            for point in polygon {
                minXD = min(minXD, point.x)
                maxXD = max(maxXD, point.x)
                minYD = min(minYD, point.y)
                maxYD = max(maxYD, point.y)
            }
            for i in 0 ..< polygon.count - 1 {
                let a = polygon[i]
                let b = polygon[i + 1]
                guard a.y != b.y else { continue }
                edges.append(Edge(x1: a.x, y1: a.y, x2: b.x, y2: b.y, direction: b.y > a.y ? 1.0 : -1.0))
            }
        }

        // All four bounds must be finite: Int(maxXD.rounded()) below traps on NaN/Inf.
        guard !edges.isEmpty, minXD.isFinite, minYD.isFinite, maxXD.isFinite, maxYD.isFinite else { return nil }

        let minX = max(0, Int(minXD.rounded(.down)))
        let maxX = min(canvasWidth - 1, Int(maxXD.rounded(.up)))
        let minY = max(0, Int(minYD.rounded(.down)))
        let maxY = min(canvasHeight - 1, Int(maxYD.rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return nil }

        let mapWidth = maxX - minX + 1
        let mapHeight = maxY - minY + 1
        var values = [Double](repeating: 0.0, count: mapWidth * mapHeight)

        let rowsPerPixel = antialiased ? Self.subsampleRows : 1
        let rowWeight = 1.0 / Double(rowsPerPixel)
        var crossings: [(x: Double, direction: Double)] = []

        for pixelY in minY ... maxY {
            let rowBase = (pixelY - minY) * mapWidth
            for sample in 0 ..< rowsPerPixel {
                let sampleY = Double(pixelY) + (Double(sample) + 0.5) / Double(rowsPerPixel)

                crossings.removeAll(keepingCapacity: true)
                for edge in edges {
                    let yTop = min(edge.y1, edge.y2)
                    let yBottom = max(edge.y1, edge.y2)
                    guard sampleY >= yTop, sampleY < yBottom else { continue }
                    let t = (sampleY - edge.y1) / (edge.y2 - edge.y1)
                    crossings.append((x: edge.x1 + t * (edge.x2 - edge.x1), direction: edge.direction))
                }
                guard crossings.count >= 2 else { continue }
                crossings.sort { $0.x < $1.x }

                var winding = 0.0
                var parityInside = false
                var inside = false
                var spanStart = 0.0
                for crossing in crossings {
                    let wasInside = inside
                    winding += crossing.direction
                    parityInside.toggle()
                    inside = (rule == .winding) ? (winding != 0.0) : parityInside
                    if !wasInside, inside {
                        spanStart = crossing.x
                    } else if wasInside, !inside {
                        addSpan(
                            from: spanStart,
                            to: crossing.x,
                            weight: rowWeight,
                            antialiased: antialiased,
                            rowBase: rowBase,
                            minX: minX,
                            mapWidth: mapWidth,
                            values: &values
                        )
                    }
                }
            }
        }

        for i in 0 ..< values.count {
            values[i] = min(1.0, values[i])
        }
        return CoverageMap(minX: minX, minY: minY, width: mapWidth, height: mapHeight, values: values)
    }

    private func addSpan(
        from x0: Double,
        to x1: Double,
        weight: Double,
        antialiased: Bool,
        rowBase: Int,
        minX: Int,
        mapWidth: Int,
        values: inout [Double]
    ) {
        let clampedX0 = max(Double(minX), x0)
        let clampedX1 = min(Double(minX + mapWidth), x1)
        guard clampedX1 > clampedX0 else { return }

        if antialiased {
            let firstPixel = max(minX, Int(clampedX0.rounded(.down)))
            let lastPixel = min(minX + mapWidth - 1, Int((clampedX1 - 1e-12).rounded(.down)))
            guard firstPixel <= lastPixel else { return }
            for pixelX in firstPixel ... lastPixel {
                let overlap = min(Double(pixelX + 1), clampedX1) - max(Double(pixelX), clampedX0)
                if overlap > 0 {
                    values[rowBase + (pixelX - minX)] += overlap * weight
                }
            }
        } else {
            // Pixel-center rule: cover pixelX when x0 <= pixelX + 0.5 < x1.
            var pixelX = max(minX, Int((clampedX0 - 0.5).rounded(.up)))
            if Double(pixelX) + 0.5 < clampedX0 {
                pixelX += 1
            }
            while pixelX <= minX + mapWidth - 1, Double(pixelX) + 0.5 < clampedX1 {
                values[rowBase + (pixelX - minX)] = 1.0
                pixelX += 1
            }
        }
    }
}
