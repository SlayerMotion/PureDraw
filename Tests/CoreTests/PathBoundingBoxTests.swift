@testable import Core
import Foundation
import Geometry
import Testing

struct PathBoundingBoxTests {
    /// Helper to check floating point equality
    private func isAlmostEqual(_ a: Double, _ b: Double, tolerance: Double = 0.0001) -> Bool {
        abs(a - b) < tolerance
    }

    private func isAlmostEqual(_ r1: Rect, _ r2: Rect) -> Bool {
        isAlmostEqual(r1.minX, r2.minX) &&
            isAlmostEqual(r1.minY, r2.minY) &&
            isAlmostEqual(r1.width, r2.width) &&
            isAlmostEqual(r1.height, r2.height)
    }

    @Test func emptyPathBounds() {
        let path = Path()
        #expect(path.boundingBox == .zero)
    }

    @Test func simpleLineBounds() {
        var path = Path()
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 100, y: 50))

        let bounds = path.boundingBox
        #expect(bounds.minX == 10)
        #expect(bounds.minY == 10)
        #expect(bounds.width == 90)
        #expect(bounds.height == 40)
    }

    @Test func quadraticCurveBounds() {
        var path = Path()
        path.move(to: Point(x: 0, y: 0))

        path.addQuadCurve(to: Point(x: 100, y: 0), control: Point(x: 50, y: 100))

        let bounds = path.boundingBox
        #expect(bounds.minX == 0)
        #expect(bounds.maxX == 100)
        #expect(bounds.minY == 0)
        #expect(isAlmostEqual(bounds.maxY, 50))
    }

    @Test func cubicCurveBounds() {
        var path = Path()
        path.move(to: Point(x: 0, y: 0))

        // Control points chosen to force an extrema.
        path.addCurve(
            to: Point(x: 100, y: 0),
            control1: Point(x: 25, y: 100),
            control2: Point(x: 75, y: -100)
        )

        let bounds = path.boundingBox

        #expect(bounds.minX == 0)
        #expect(bounds.maxX == 100)
        #expect(bounds.minY < 0)
        #expect(bounds.maxY > 0)

        // Mathematically, evaluating the cubic Bézier polynomial at the roots of
        // its derivative for this specific curve yields extrema at roughly +- 28.867.
        // This proves the calculus is catching the actual curve limits, not just
        // the endpoints (0,0) or naively the control points (+- 100).
        #expect(isAlmostEqual(bounds.maxY, 28.8675, tolerance: 0.001))
        #expect(isAlmostEqual(bounds.minY, -28.8675, tolerance: 0.001))
    }
}
