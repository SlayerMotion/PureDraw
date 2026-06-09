@testable import Core
import Foundation
import Geometry
import Testing
import Validation

struct PathTests {
    @Test func pathConstruction() {
        var path = Path()
        #expect(path.isEmpty)

        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 100, y: 10))
        path.addCurve(to: Point(x: 100, y: 100), control1: Point(x: 150, y: 50), control2: Point(x: 150, y: 100))
        path.closeSubpath()

        #expect(path.elements.count == 4)

        if case let .move(p) = path.elements[0] {
            #expect(p.x == 10 && p.y == 10)
        } else {
            Issue.record("Expected .move")
        }

        if case .close = path.elements[3] {
            // Expected
        } else {
            Issue.record("Expected .close")
        }
    }

    @Test func pathTransformation() {
        var path = Path()
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 20, y: 20))

        let t = Geometry.AffineTransform.scale(x: 2, y: 3)
        let transformedPath = path.applying(t)

        #expect(transformedPath.elements.count == 2)

        if case let .move(p) = transformedPath.elements[0] {
            #expect(p.x == 20 && p.y == 30)
        } else {
            Issue.record("Expected .move")
        }

        if case let .line(p) = transformedPath.elements[1] {
            #expect(p.x == 40 && p.y == 60)
        } else {
            Issue.record("Expected .line")
        }
    }

    @Test func pathConstructionWithEllipse() {
        var path = Path()
        path.addEllipse(in: Rect(x: 10, y: 10, width: 100, height: 100))

        // Ellipse has a Move, 4 Cubic Curves, and a Close = 6 elements
        #expect(path.elements.count == 6)

        if case let .move(p) = path.elements[0] {
            #expect(p.x == 110 && p.y == 60) // Start point: cx + rx, cy
        } else {
            Issue.record("Expected .move")
        }
    }

    @Test func pathConstructionWithRoundedRect() {
        var path = Path()
        path.addRoundedRect(in: Rect(x: 0, y: 0, width: 100, height: 100), cornerWidth: 10, cornerHeight: 10)

        // Rounded rect has: 1 Move, 4 Lines, 4 Curves, 1 Close = 10 elements
        #expect(path.elements.count == 10)
    }

    @Test func pathConstructionWithArcs() {
        // Clockwise arc from 0 to pi/2 (90 degrees)
        var path1 = Path()
        path1.addArc(center: Point(x: 0, y: 0), radius: 10, startAngle: 0, endAngle: .pi / 2.0, clockwise: true)

        // 90 degrees fits in 1 segment -> Move + 1 Curve = 2 elements
        #expect(path1.elements.count == 2)

        if case let .move(p) = path1.elements[0] {
            #expect(p.x == 10 && p.y == 0) // start point
        } else {
            Issue.record("Expected .move")
        }

        if case let .cubicCurve(to, _, _) = path1.elements[1] {
            #expect(abs(to.x) < 1e-9) // approx 0
            #expect(abs(to.y - 10) < 1e-9) // approx 10
        } else {
            Issue.record("Expected .cubicCurve")
        }

        // Counter-clockwise arc
        var path2 = Path()
        path2.addArc(center: Point(x: 0, y: 0), radius: 10, startAngle: .pi / 2.0, endAngle: 0, clockwise: false)
        #expect(path2.elements.count == 2)
    }

    @Test func pathConstructionWithTangentArc() {
        var path = Path()
        path.move(to: Point(x: 0, y: 0))
        path.addArc(tangent1End: Point(x: 100, y: 0), tangent2End: Point(x: 100, y: 100), radius: 50)

        // Starts at 0,0. Goes towards 100,0. Tangent point Q1 will be at 100 - 50 = 50,0.
        // Arc goes to tangent point Q2 at 100, 50.
        #expect(path.elements.count == 3)

        if case let .line(p) = path.elements[1] {
            #expect(abs(p.x - 50) < 1e-9)
            #expect(abs(p.y) < 1e-9)
        } else {
            Issue.record("Expected .line to tangent point")
        }

        if case let .cubicCurve(to, _, _) = path.elements[2] {
            #expect(abs(to.x - 100) < 1e-9)
            #expect(abs(to.y - 50) < 1e-9)
        } else {
            Issue.record("Expected .cubicCurve representing the arc")
        }
    }
}
