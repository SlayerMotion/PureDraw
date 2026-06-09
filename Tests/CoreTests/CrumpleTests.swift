@testable import Core
import Foundation
import Geometry
import Testing

struct CrumpleTests {
    @Test func pathSubdivision() {
        var path = Path()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 100, y: 0))

        // Subdivide with max length 15.
        // 100 / 15 = 6.66 -> should be 7 segments
        let subdivided = path.subdivided(maxSegmentLength: 15)

        #expect(subdivided.elements.count == 8) // 1 move + 7 lines

        // Let's verify the first and last elements
        if case let .move(pt) = subdivided.elements.first {
            #expect(pt.x == 0 && pt.y == 0)
        } else {
            Issue.record("Expected first element to be a move")
        }

        if case let .line(pt) = subdivided.elements.last {
            #expect(pt.x == 100 && pt.y == 0)
        } else {
            Issue.record("Expected last element to be a line")
        }
    }

    @Test func crumpleDeformerPinchAndWrinkles() {
        let center = Point(x: 250, y: 250)
        let deformer = CrumpleDeformer(center: center, radius: 100.0, pinchStrength: 0.5, wrinkleStrength: 1.0)

        let p1 = Point(x: 200, y: 200)
        let transformed1 = deformer.transform(p1)

        // Transformed point should be different
        #expect(transformed1 != p1)

        // Point right at center should experience no pinch but should experience wrinkles
        let pCenter = Point(x: 250, y: 250)
        let transformedCenter = deformer.transform(pCenter)
        #expect(transformedCenter != pCenter)
    }

    @Test func deformingPath() {
        var path = Path()
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 20, y: 20))

        let deformer = CrumpleDeformer(center: Point(x: 15, y: 15), radius: 50)
        let deformedPath = path.deforming { deformer.transform($0) }

        #expect(deformedPath.elements.count == 2)

        if case let .move(p) = deformedPath.elements[0] {
            #expect(p != Point(x: 10, y: 10))
        }
        if case let .line(p) = deformedPath.elements[1] {
            #expect(p != Point(x: 20, y: 20))
        }
    }
}
