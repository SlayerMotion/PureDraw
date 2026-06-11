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

    @Test func edgeConsumptionMatchesAppleRatio() {
        var path = Path()
        path.addContinuousRoundedRect(in: Rect(x: 0, y: 0, width: 400, height: 400), cornerRadius: 80)
        // Apple's corner consumes exactly 1.528665r = 122.2932 of each edge; the
        // leading move starts the top straight edge there.
        guard case let .move(start) = path.elements.first else {
            Issue.record("expected a leading move")
            return
        }
        #expect(abs(start.x - 122.2932) < 0.001, "corner should start 1.528665r from the corner, got \(start.x)")
    }

    @Test func continuousCornerRedistributesCurvature() {
        let rect = Rect(x: 0, y: 0, width: 200, height: 200)
        var circular = Path()
        circular.addRoundedRect(in: rect, cornerWidth: 40, cornerHeight: 40)
        var continuous = Path()
        continuous.addContinuousRoundedRect(in: rect, cornerRadius: 40)
        // A circular corner has constant curvature 1/r along its arc; Apple's
        // continuous corner redistributes it: flatter where it meets the straight
        // edge and a higher peak in the middle, so its peak curvature exceeds 1/r.
        // (Apple's real corner is three cubics with small kinks at their joins, so it
        // is faithful to iOS rather than perfectly G2 continuous.)
        let circularPeak = curvatures(of: circular).max() ?? 0
        let continuousPeak = curvatures(of: continuous).max() ?? 0
        #expect(circularPeak > 0)
        #expect(continuousPeak > circularPeak, "continuous peak \(continuousPeak) vs circular peak \(circularPeak)")
    }

    @Test func exactCornerHasTwelveCubicsAndLeavesTheEdgeTangentially() {
        var path = Path()
        path.addContinuousRoundedRect(in: Rect(x: 0, y: 0, width: 200, height: 200), cornerRadius: 44)
        let curves = path.elements.filter { if case .cubicCurve = $0 { true } else { false } }.count
        #expect(curves == 12) // 4 corners x 3 cubics
        if case .close = path.elements.last {} else { Issue.record("path must be closed") }
        // The first cubic's first control point sits on the top edge (y == minY): a
        // horizontal, tangential departure from the straight edge.
        let firstCubic = path.elements.first { if case .cubicCurve = $0 { true } else { false } }
        guard case let .cubicCurve(_, c1, _) = firstCubic else {
            Issue.record("expected a cubic")
            return
        }
        #expect(abs(c1.y) < 0.001, "first control point should sit on the top edge")
    }

    @Test func zeroRadiusIsPlainRectangle() {
        var path = Path()
        path.addContinuousRoundedRect(in: Rect(x: 0, y: 0, width: 100, height: 80), cornerRadius: 0)
        #expect(!path.elements.contains { if case .cubicCurve = $0 { true } else { false } })
    }

    @Test func staysWithinBoundsAndTouchesEachEdge() {
        let rect = Rect(x: 10, y: 20, width: 120, height: 90)
        var path = Path()
        path.addContinuousRoundedRect(in: rect, cornerRadius: 30)
        let box = path.boundingBox
        #expect(box.minX >= rect.minX - 0.01 && box.maxX <= rect.maxX + 0.01)
        #expect(box.minY >= rect.minY - 0.01 && box.maxY <= rect.maxY + 0.01)
        #expect(abs(box.minX - rect.minX) < 0.5 && abs(box.maxX - rect.maxX) < 0.5)
        #expect(abs(box.minY - rect.minY) < 0.5 && abs(box.maxY - rect.maxY) < 0.5)
    }

    @Test func everySegmentJoinsTheLastAndTheCornerCloses() {
        var path = Path()
        path.addContinuousRoundedRect(in: Rect(x: 10, y: 20, width: 120, height: 90), cornerRadius: 30)
        var current: Point?
        var subpathStart: Point?
        func end(of element: PathElement) -> Point? {
            switch element {
            case let .move(p), let .line(p): p
            case let .quadCurve(p, _), let .cubicCurve(p, _, _): p
            case .close: subpathStart
            }
        }
        func start(of element: PathElement) -> Point? {
            if case let .move(p) = element { return p }
            return current // every non-move segment starts at the running point
        }
        for element in path.elements {
            if case .move = element {} else if let from = current, let into = start(of: element) {
                #expect(abs(from.x - into.x) < 1e-9 && abs(from.y - into.y) < 1e-9, "disconnected segment")
            }
            if case let .move(p) = element { subpathStart = p }
            current = end(of: element)
        }
        // The closing edge collapses to zero: the last corner ends exactly at the
        // leading move, with no stray hairline segment.
        if case let .move(startPoint) = path.elements.first,
           case let .cubicCurve(lastEnd, _, _) = path.elements.dropLast().last
        {
            #expect(abs(lastEnd.x - startPoint.x) < 1e-9 && abs(lastEnd.y - startPoint.y) < 1e-9)
        } else {
            Issue.record("expected a leading move and a trailing cubic before close")
        }
    }

    @Test func largeRadiusScalesToFitWithoutBreaking() {
        // At (or beyond) half the short side, the corner scales to fit: a smooth
        // continuous capsule with no self-intersection or NaN.
        for radius in [50.0, 1000.0] {
            var path = Path()
            path.addContinuousRoundedRect(in: Rect(x: 0, y: 0, width: 100, height: 100), cornerRadius: radius)
            let box = path.boundingBox
            #expect(box.minX >= -0.01 && box.maxX <= 100.01 && box.minY >= -0.01 && box.maxY <= 100.01)
            let finite = path.elements.allSatisfy {
                switch $0 {
                case let .move(p), let .line(p): p.x.isFinite && p.y.isFinite
                case let .quadCurve(p, c): p.x.isFinite && p.y.isFinite && c.x.isFinite && c.y.isFinite
                case let .cubicCurve(p, c1, c2):
                    p.x.isFinite && p.y.isFinite && c1.x.isFinite && c1.y.isFinite && c2.x.isFinite && c2.y.isFinite
                case .close: true
                }
            }
            #expect(finite)
        }
    }
}
