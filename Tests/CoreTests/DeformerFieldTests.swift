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

struct PinchDeformerTests {
    private let center = Point(x: 100, y: 100)

    @Test func `the center is a fixed point`() {
        let pinch = PinchDeformer(center: center, radius: 50, amount: 0.5)
        #expect(pinch.transform(center) == center)
    }

    @Test func `points at or beyond the radius are untouched`() {
        let pinch = PinchDeformer(center: center, radius: 50, amount: 0.5)
        #expect(pinch.transform(Point(x: 160, y: 100)) == Point(x: 160, y: 100)) // distance 60 > 50
        #expect(pinch.transform(Point(x: 150, y: 100)) == Point(x: 150, y: 100)) // distance 50 == radius
    }

    @Test func `a zero amount is the identity`() {
        let pinch = PinchDeformer(center: center, radius: 50, amount: 0)
        #expect(pinch.transform(Point(x: 120, y: 130)) == Point(x: 120, y: 130))
    }

    @Test func `a positive amount pulls the point inward`() {
        let pinch = PinchDeformer(center: center, radius: 50, amount: 0.6)
        let point = Point(x: 130, y: 100) // distance 30 < 50
        #expect(distance(pinch.transform(point), center) < distance(point, center))
    }

    @Test func `a negative amount pushes the point outward`() {
        let bloat = PinchDeformer(center: center, radius: 50, amount: -0.6)
        let point = Point(x: 130, y: 100) // distance 30 < 50
        #expect(distance(bloat.transform(point), center) > distance(point, center))
    }

    @Test func `the pinch keeps each point on its ray from the center`() {
        let pinch = PinchDeformer(center: center, radius: 50, amount: 0.6)
        let point = Point(x: 120, y: 130)
        let moved = pinch.transform(point)
        let before = atan2(point.y - center.y, point.x - center.x)
        let after = atan2(moved.y - center.y, moved.x - center.x)
        #expect(abs(before - after) < 1e-9)
    }
}

struct RippleDeformerTests {
    private let center = Point(x: 100, y: 100)

    @Test func `the center is a fixed point`() {
        let ripple = RippleDeformer(center: center, radius: 50, amplitude: 0.1, waves: 4)
        #expect(ripple.transform(center) == center)
    }

    @Test func `points at or beyond the radius are untouched`() {
        let ripple = RippleDeformer(center: center, radius: 50, amplitude: 0.1, waves: 4)
        #expect(ripple.transform(Point(x: 160, y: 100)) == Point(x: 160, y: 100)) // distance 60 > 50
        #expect(ripple.transform(Point(x: 150, y: 100)) == Point(x: 150, y: 100)) // distance 50 == radius
    }

    @Test func `a zero amplitude is the identity`() {
        let ripple = RippleDeformer(center: center, radius: 50, amplitude: 0, waves: 4)
        #expect(ripple.transform(Point(x: 120, y: 130)) == Point(x: 120, y: 130))
    }

    @Test func `the ripple keeps each point on its ray from the center`() {
        let ripple = RippleDeformer(center: center, radius: 50, amplitude: 0.1, waves: 4)
        let point = Point(x: 120, y: 130)
        let moved = ripple.transform(point)
        let before = atan2(point.y - center.y, point.x - center.x)
        let after = atan2(moved.y - center.y, moved.x - center.x)
        #expect(abs(before - after) < 1e-9)
    }
}

/// The validators check a deformer's parameters are finite; this checks the field's output is too. A NaN
/// or infinite point cannot be rendered, so every deformer at strong settings must map a grid of finite
/// points, including the center and points well beyond the radius, to finite points.
struct DeformerFinitenessTests {
    @Test func `every deformer maps finite points to finite points`() {
        let center = Point(x: 0, y: 0)
        let radius = 100.0
        let fields: [(name: String, transform: (Point) -> Point)] = [
            ("crumple", CrumpleDeformer(center: center, radius: radius, pinchStrength: 0.6, wrinkleStrength: 1.5).transform),
            ("swirl", SwirlDeformer(center: center, radius: radius, angle: 5).transform),
            ("pageCurl", PageCurlDeformer(center: center, radius: radius, curl: 0.8, tightness: 0.15).transform),
            ("shrivel", ShrivelDeformer(center: center, radius: radius, shrink: 0.8, wrinkle: 2).transform),
            ("pinch", PinchDeformer(center: center, radius: radius, amount: 0.8).transform),
            ("bloat", PinchDeformer(center: center, radius: radius, amount: -0.8).transform),
            ("ripple", RippleDeformer(center: center, radius: radius, amplitude: 0.2, waves: 6).transform),
        ]
        for x in stride(from: -150.0, through: 150, by: 10) {
            for y in stride(from: -150.0, through: 150, by: 10) {
                let point = Point(x: x, y: y)
                for field in fields {
                    let mapped = field.transform(point)
                    #expect(mapped.x.isFinite && mapped.y.isFinite, "\(field.name) produced a non-finite point at \(point)")
                }
            }
        }
    }
}

/// A non-positive radius has no field: every deformer returns the point unchanged, so it never divides by
/// zero or overflows to a non-finite displacement. The validators allow a finite-but-negative radius, so
/// the transform itself has to guard, and all four now do.
struct DeformerRadiusGuardTests {
    @Test func `a non-positive radius is the identity for every deformer`() {
        let center = Point(x: 10, y: 20)
        let point = Point(x: 40, y: -5)
        for radius in [0.0, -5.0] {
            #expect(CrumpleDeformer(center: center, radius: radius, pinchStrength: 0.6, wrinkleStrength: 1.5).transform(point) == point)
            #expect(SwirlDeformer(center: center, radius: radius, angle: 4).transform(point) == point)
            #expect(PageCurlDeformer(center: center, radius: radius, curl: 0.6, tightness: 0.2).transform(point) == point)
            #expect(ShrivelDeformer(center: center, radius: radius, shrink: 0.5, wrinkle: 1).transform(point) == point)
            #expect(PinchDeformer(center: center, radius: radius, amount: 0.6).transform(point) == point)
            #expect(RippleDeformer(center: center, radius: radius, amplitude: 0.1, waves: 4).transform(point) == point)
        }
    }
}
