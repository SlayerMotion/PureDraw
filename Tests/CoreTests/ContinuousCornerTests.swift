//
//  ContinuousCornerTests.swift
//  PureDraw
//

@testable import Core
import Foundation
import Geometry
import Testing

struct ContinuousCornerTests {
    /// Discrete curvature (turning angle per unit length) sampled along a
    /// densely flattened path, ignoring the closing wrap.
    private func curvatures(of path: Path) -> [Double] {
        let pts = path.subdivided(maxSegmentLength: 0.25).toPolygons().first ?? []
        guard pts.count > 3 else { return [] }
        var result: [Double] = []
        for i in 1 ..< pts.count - 1 {
            let a = pts[i - 1], b = pts[i], c = pts[i + 1]
            let v1 = Point(x: b.x - a.x, y: b.y - a.y)
            let v2 = Point(x: c.x - b.x, y: c.y - b.y)
            let l1 = (v1.x * v1.x + v1.y * v1.y).squareRoot()
            let l2 = (v2.x * v2.x + v2.y * v2.y).squareRoot()
            guard l1 > 1e-9, l2 > 1e-9 else { continue }
            let cross = v1.x * v2.y - v1.y * v2.x
            let dot = v1.x * v2.x + v1.y * v2.y
            let angle = atan2(cross, dot)
            result.append(abs(angle) / ((l1 + l2) / 2))
        }
        return result
    }

    @Test func cornerConsumesMoreThanRadius() {
        var path = Path()
        path.addContinuousRoundedRect(in: Rect(x: 0, y: 0, width: 200, height: 200), cornerRadius: 40, smoothing: 0.6)
        // The top straight edge runs from x = p to x = 200 - p, with
        // p = 1.6 * 40 = 64. The move-to starts the straight edge at x = p.
        guard case let .move(start) = path.elements.first else {
            Issue.record("expected a leading move")
            return
        }
        #expect(abs(start.x - 64) < 0.01, "corner should start 1.6r from the corner, got \(start.x)")
    }

    @Test func curvatureRampsInsteadOfJumping() {
        let rect = Rect(x: 0, y: 0, width: 200, height: 200)

        var circular = Path()
        circular.addRoundedRect(in: rect, cornerWidth: 40, cornerHeight: 40)

        var continuous = Path()
        continuous.addContinuousRoundedRect(in: rect, cornerRadius: 40, smoothing: 0.6)

        /// The largest single jump in curvature between adjacent samples. A
        /// circular corner jumps from 0 to 1/r at the straight-to-arc junction;
        /// a continuous corner spreads that change out, so its largest jump is
        /// markedly smaller.
        func maxJump(_ ks: [Double]) -> Double {
            var m = 0.0
            for i in 1 ..< ks.count {
                m = max(m, abs(ks[i] - ks[i - 1]))
            }
            return m
        }

        let circularJump = maxJump(curvatures(of: circular))
        let continuousJump = maxJump(curvatures(of: continuous))

        #expect(circularJump > 0)
        // Measured ~0.55x: the continuous corner spreads the curvature change
        // out instead of jumping it at a single junction.
        #expect(
            continuousJump < circularJump * 0.7,
            "continuous corner should ramp curvature: continuous \(continuousJump) vs circular \(circularJump)"
        )
    }

    @Test func zeroRadiusIsPlainRectangle() {
        var path = Path()
        path.addContinuousRoundedRect(in: Rect(x: 0, y: 0, width: 100, height: 80), cornerRadius: 0)
        // move + 4 lines + close = 6 elements, no curves.
        let hasCurve = path.elements.contains { if case .cubicCurve = $0 { return true }
            return false
        }
        #expect(!hasCurve)
    }

    @Test func staysWithinBounds() {
        let rect = Rect(x: 10, y: 20, width: 120, height: 90)
        var path = Path()
        path.addContinuousRoundedRect(in: rect, cornerRadius: 30, smoothing: 0.7)
        let box = path.boundingBox
        #expect(box.minX >= rect.minX - 0.01 && box.maxX <= rect.maxX + 0.01)
        #expect(box.minY >= rect.minY - 0.01 && box.maxY <= rect.maxY + 0.01)
        // It should reach each edge (corners touch the sides at the midpoints).
        #expect(abs(box.minX - rect.minX) < 0.5 && abs(box.maxX - rect.maxX) < 0.5)
    }
}
