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

    @Test func pathConstructionWithLines() {
        var path = Path()
        let points = [Point(x: 10, y: 10), Point(x: 20, y: 20), Point(x: 30, y: 10)]
        path.addLines(between: points)

        #expect(path.elements.count == 3)
        if case let .move(p) = path.elements[0] {
            #expect(p == Point(x: 10, y: 10))
        } else {
            Issue.record("Expected .move")
        }
        if case let .line(p) = path.elements[1] {
            #expect(p == Point(x: 20, y: 20))
        } else {
            Issue.record("Expected .line")
        }
        if case let .line(p) = path.elements[2] {
            #expect(p == Point(x: 30, y: 10))
        } else {
            Issue.record("Expected .line")
        }
    }

    @Test func pathCurrentPoint() {
        var path = Path()
        #expect(path.currentPoint == Point.zero)

        path.move(to: Point(x: 10, y: 15))
        #expect(path.currentPoint == Point(x: 10, y: 15))

        path.addLine(to: Point(x: 100, y: 20))
        #expect(path.currentPoint == Point(x: 100, y: 20))

        path.addQuadCurve(to: Point(x: 200, y: 30), control: Point(x: 150, y: 25))
        #expect(path.currentPoint == Point(x: 200, y: 30))

        path.addCurve(to: Point(x: 300, y: 40), control1: Point(x: 220, y: 35), control2: Point(x: 280, y: 45))
        #expect(path.currentPoint == Point(x: 300, y: 40))

        path.closeSubpath()
        #expect(path.currentPoint == Point(x: 10, y: 15))

        path.move(to: Point(x: 50, y: 60))
        #expect(path.currentPoint == Point(x: 50, y: 60))
    }

    @Test func pathContainment() {
        // 1. Simple Rect Path
        var rectPath = Path()
        rectPath.addRect(Rect(x: 10, y: 10, width: 100, height: 100))

        #expect(rectPath.contains(Point(x: 50, y: 50), using: .winding))
        #expect(rectPath.contains(Point(x: 50, y: 50), using: .evenOdd))

        #expect(!rectPath.contains(Point(x: 5, y: 5), using: .winding))
        #expect(!rectPath.contains(Point(x: 150, y: 50), using: .winding))

        // 2. Simple Triangle Path
        var trianglePath = Path()
        trianglePath.move(to: Point(x: 0, y: 0))
        trianglePath.addLine(to: Point(x: 100, y: 0))
        trianglePath.addLine(to: Point(x: 50, y: 100))
        trianglePath.closeSubpath()

        #expect(trianglePath.contains(Point(x: 50, y: 30), using: .winding))
        #expect(!trianglePath.contains(Point(x: 10, y: 80), using: .winding))

        // 3. Donut Path (Nested squares)
        // Outer: Clockwise (0,0) -> (100,0) -> (100,100) -> (0,100) -> close
        var outerPath = Path()
        outerPath.move(to: Point(x: 0, y: 0))
        outerPath.addLine(to: Point(x: 100, y: 0))
        outerPath.addLine(to: Point(x: 100, y: 100))
        outerPath.addLine(to: Point(x: 0, y: 100))
        outerPath.closeSubpath()

        // Inner: Clockwise (same direction) (25,25) -> (75,25) -> (75,75) -> (25,75) -> close
        var donutSame = outerPath
        donutSame.move(to: Point(x: 25, y: 25))
        donutSame.addLine(to: Point(x: 75, y: 25))
        donutSame.addLine(to: Point(x: 75, y: 75))
        donutSame.addLine(to: Point(x: 25, y: 75))
        donutSame.closeSubpath()

        // Inner: Counter-Clockwise (opposite direction) (25,25) -> (25,75) -> (75,75) -> (75,25) -> close
        var donutOpposite = outerPath
        donutOpposite.move(to: Point(x: 25, y: 25))
        donutOpposite.addLine(to: Point(x: 25, y: 75))
        donutOpposite.addLine(to: Point(x: 75, y: 75))
        donutOpposite.addLine(to: Point(x: 75, y: 25))
        donutOpposite.closeSubpath()

        let holePoint = Point(x: 50, y: 50)
        let ringPoint = Point(x: 15, y: 15)

        // Even-Odd: hole point must be OUTSIDE (toggle twice: inside -> outside)
        #expect(!donutSame.contains(holePoint, using: .evenOdd))
        #expect(!donutOpposite.contains(holePoint, using: .evenOdd))
        #expect(donutSame.contains(ringPoint, using: .evenOdd))

        // Winding:
        // same direction: hole point winding number is 2 (non-zero) -> INSIDE
        #expect(donutSame.contains(holePoint, using: .winding))
        // opposite direction: hole point winding number is 1 - 1 = 0 -> OUTSIDE
        #expect(!donutOpposite.contains(holePoint, using: .winding))
    }
}
