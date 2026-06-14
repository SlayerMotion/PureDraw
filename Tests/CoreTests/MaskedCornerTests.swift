//
//  MaskedCornerTests.swift
//  PureDraw
//

@testable import Core
import Foundation
import Geometry
import Testing

/// `addRoundedRect`/`addContinuousRoundedRect` round only the corners in the
/// `corners` mask; the rest stay square. A square corner leaves the exact rect
/// vertex on the path; a rounded corner pulls the path ~0.41r away from it.
struct MaskedCornerTests {
    private let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    private let radius = 20.0

    /// Minimum distance from `vertex` to the flattened outline of `path`.
    private func distance(from vertex: Point, to path: Path) -> Double {
        let pts = path.subdivided(maxSegmentLength: 0.25).toPolygons().first ?? []
        var best = Double.infinity
        for p in pts {
            let d = ((p.x - vertex.x) * (p.x - vertex.x) + (p.y - vertex.y) * (p.y - vertex.y)).squareRoot()
            best = min(best, d)
        }
        return best
    }

    private var corners: (tl: Point, tr: Point, br: Point, bl: Point) {
        (Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 100, y: 100), Point(x: 0, y: 100))
    }

    @Test func circularRoundsOnlySelectedCorner() {
        var path = Path()
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius, corners: [.minXMinY])
        let c = corners
        #expect(distance(from: c.tl, to: path) > 5) //   rounded: pulled ~0.41*20 away
        #expect(distance(from: c.tr, to: path) < 0.5) //  square: vertex on the path
        #expect(distance(from: c.br, to: path) < 0.5)
        #expect(distance(from: c.bl, to: path) < 0.5)
    }

    @Test func continuousRoundsOnlySelectedCorner() {
        var path = Path()
        path.addContinuousRoundedRect(in: rect, cornerRadius: radius, corners: [.minXMinY])
        let c = corners
        #expect(distance(from: c.tl, to: path) > 5)
        #expect(distance(from: c.tr, to: path) < 0.5)
        #expect(distance(from: c.br, to: path) < 0.5)
        #expect(distance(from: c.bl, to: path) < 0.5)
    }

    @Test func topCornersOnly() {
        var path = Path()
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius, corners: [.minXMinY, .maxXMinY])
        let c = corners
        #expect(distance(from: c.tl, to: path) > 5) // both top corners rounded
        #expect(distance(from: c.tr, to: path) > 5)
        #expect(distance(from: c.bl, to: path) < 0.5) // both bottom corners square
        #expect(distance(from: c.br, to: path) < 0.5)
    }

    @Test func defaultRoundsAllFourCorners() {
        var explicit = Path()
        explicit.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius, corners: .all)
        var implicit = Path()
        implicit.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        // The default parameter is .all, so the two paths are identical.
        #expect(explicit.elements.count == implicit.elements.count)
        let c = corners
        for v in [c.tl, c.tr, c.br, c.bl] {
            #expect(distance(from: v, to: explicit) > 5) // every corner rounded
        }
    }
}
