@testable import Core
import Foundation
import Geometry
import Testing

/// Behavioural proofs for the non-linear deformer fields the trinkets are built on. Crumple already has
/// its own test; these cover the swirl, page curl, and shrivel forward point maps. Each field has a sharp
/// contract the renderer relies on: a fixed region that does not move, points beyond the influence left
/// untouched, an identity at zero strength, and a geometric invariant (distance- or ray-preserving).
private func distance(_ a: Point, _ b: Point) -> Double {
    (((a.x - b.x) * (a.x - b.x)) + ((a.y - b.y) * (a.y - b.y))).squareRoot()
}

struct SwirlDeformerTests {
    private let center = Point(x: 100, y: 100)

    @Test func `the center is a fixed point`() {
        let swirl = SwirlDeformer(center: center, radius: 50, angle: .pi)
        #expect(swirl.transform(center) == center)
    }

    @Test func `points at or beyond the radius are untouched`() {
        let swirl = SwirlDeformer(center: center, radius: 50, angle: .pi)
        #expect(swirl.transform(Point(x: 160, y: 100)) == Point(x: 160, y: 100)) // distance 60 > 50
        #expect(swirl.transform(Point(x: 150, y: 100)) == Point(x: 150, y: 100)) // distance 50 == radius
    }

    @Test func `the swirl preserves each point's distance from the center`() {
        let swirl = SwirlDeformer(center: center, radius: 50, angle: .pi)
        let point = Point(x: 120, y: 130) // distance ~36 < 50, so it rotates
        let moved = swirl.transform(point)
        #expect(moved != point)
        #expect(abs(distance(moved, center) - distance(point, center)) < 1e-9)
    }

    @Test func `a zero angle is the identity`() {
        let swirl = SwirlDeformer(center: center, radius: 50, angle: 0)
        #expect(swirl.transform(Point(x: 120, y: 130)) == Point(x: 120, y: 130))
    }
}

struct PageCurlDeformerTests {
    private let center = Point(x: 0, y: 0)

    @Test func `points left of the curl line are untouched`() {
        // curl 0.5 puts the curl line at axisX = center.x + radius - curl*2*radius = 0.
        let curl = PageCurlDeformer(center: center, radius: 10, curl: 0.5, tightness: 0.25)
        #expect(curl.transform(Point(x: -3, y: 2)) == Point(x: -3, y: 2))
        #expect(curl.transform(Point(x: 0, y: 2)) == Point(x: 0, y: 2)) // exactly on the line, not past it
    }

    @Test func `no curl leaves the sheet flat`() {
        // curl 0 puts the line at the right edge (axisX = radius), so the whole sheet is untouched.
        let curl = PageCurlDeformer(center: center, radius: 10, curl: 0, tightness: 0.25)
        #expect(curl.transform(Point(x: 5, y: 3)) == Point(x: 5, y: 3))
    }

    @Test func `a point past the curl line wraps onto the cylinder and lifts`() {
        let curl = PageCurlDeformer(center: center, radius: 10, curl: 0.5, tightness: 0.25)
        // axisX 0, cylinder = max(0.0001, 0.25*10) = 2.5.
        let point = Point(x: 4, y: 5)
        let moved = curl.transform(point)
        #expect(moved != point)
        #expect(moved.x >= 0 && moved.x <= 2.5 + 1e-9) // x compresses into [axisX, axisX + cylinder]
        #expect(moved.y <= point.y) // y lifts up off the page
    }

    @Test func `a zero radius is the identity`() {
        let curl = PageCurlDeformer(center: center, radius: 0, curl: 0.5)
        #expect(curl.transform(Point(x: 4, y: 5)) == Point(x: 4, y: 5))
    }
}

struct ShrivelDeformerTests {
    private let center = Point(x: 50, y: 50)

    @Test func `the center is untouched`() {
        let shrivel = ShrivelDeformer(center: center, radius: 40, shrink: 0.4, wrinkle: 1.0)
        #expect(shrivel.transform(center) == center)
    }

    @Test func `no shrink and no wrinkle is the identity`() {
        let shrivel = ShrivelDeformer(center: center, radius: 40, shrink: 0, wrinkle: 0)
        #expect(shrivel.transform(Point(x: 70, y: 60)) == Point(x: 70, y: 60))
    }

    @Test func `the shrivel keeps each point on its ray from the center`() {
        let shrivel = ShrivelDeformer(center: center, radius: 40, shrink: 0.4, wrinkle: 1.0)
        let point = Point(x: 70, y: 60)
        let moved = shrivel.transform(point)
        let before = atan2(point.y - center.y, point.x - center.x)
        let after = atan2(moved.y - center.y, moved.x - center.x)
        #expect(abs(before - after) < 1e-9)
    }

    @Test func `with shrink and no wrinkle the point pulls inward`() {
        let shrivel = ShrivelDeformer(center: center, radius: 40, shrink: 0.4, wrinkle: 0)
        let point = Point(x: 80, y: 50) // distance 30 < 40
        #expect(distance(shrivel.transform(point), center) < distance(point, center))
    }
}
