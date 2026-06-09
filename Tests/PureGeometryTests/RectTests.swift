import Foundation
@testable import PureGeometry
import Testing

struct RectTests {
    @Test func rectStandardization() {
        let r1 = Rect(x: 100, y: 100, width: -30, height: -50)
        let std = r1.standardized()

        #expect(std.origin.x == 70)
        #expect(std.origin.y == 50)
        #expect(std.width == 30)
        #expect(std.height == 50)
        #expect(std.isEmpty == false)
    }

    @Test func rectIntegral() {
        let r1 = Rect(x: 0.5, y: 0.2, width: 99.9, height: 105.5)
        let integral = r1.integral()

        #expect(integral.origin.x == 0)
        #expect(integral.origin.y == 0)
        #expect(integral.width == 101)
        #expect(integral.height == 106)
    }

    @Test func rectInsetAndOffset() {
        let r1 = Rect(x: 0, y: 0, width: 20, height: 10)
        let inset = r1.insetBy(dx: 3, dy: 2)

        #expect(inset.origin.x == 3)
        #expect(inset.origin.y == 2)
        #expect(inset.width == 14)
        #expect(inset.height == 6)

        let shifted = r1.offsetBy(dx: 10, dy: 20)
        #expect(shifted.origin.x == 10)
        #expect(shifted.origin.y == 20)
        #expect(shifted.width == 20)
        #expect(shifted.height == 10)
    }

    @Test func rectCentering() {
        let inner = Rect(x: 0, y: 0, width: 50, height: 50)
        let outer = Rect(x: 10, y: 20, width: 100, height: 100)
        let centered = inner.centered(in: outer)

        // expected center coordinates: outer.origin + (outer.size - inner.size)/2
        // x = 10 + (100 - 50)/2 = 15
        // y = 20 + (100 - 50)/2 = 45
        #expect(centered.origin.x == 35) // wait: outer.origin.x is 10. floor((100 - 50)/2) = 25. 10 + 25 = 35. Correct!
        #expect(centered.origin.y == 45) // outer.origin.y is 20. floor((100 - 50)/2) = 25. 20 + 25 = 45. Correct!
        #expect(centered.width == 50)
        #expect(centered.height == 50)
    }

    @Test func rectDividing() {
        let startingRect = Rect(x: 37, y: 42, width: 300, height: 100)
        let (slice, remainder) = startingRect.divided(at: 100, from: .minX)

        #expect(slice.origin.x == 37)
        #expect(slice.origin.y == 42)
        #expect(slice.width == 100)
        #expect(slice.height == 100)

        #expect(remainder.origin.x == 137)
        #expect(remainder.origin.y == 42)
        #expect(remainder.width == 200)
        #expect(remainder.height == 100)
    }

    @Test func rectRelationships() {
        let r1 = Rect(x: 0, y: 0, width: 200, height: 100)
        let t1 = Rect(x: 10, y: 20, width: 80, height: 80)
        let t2 = Rect(x: 180, y: 20, width: 100, height: 40)

        #expect(r1.contains(Point(x: 50, y: 50)) == true)
        #expect(r1.contains(Point(x: 250, y: 50)) == false)

        #expect(r1.contains(t1) == true)
        #expect(r1.contains(t2) == false)

        #expect(r1.intersects(t1) == true)
        #expect(r1.intersects(t2) == true)
    }

    @Test func rectUnionAndIntersection() {
        let r1 = Rect(x: 10, y: 20, width: 80, height: 80)
        let r2 = Rect(x: 180, y: 20, width: 100, height: 40)

        let unionRect = r1.union(r2)
        #expect(unionRect.origin.x == 10)
        #expect(unionRect.origin.y == 20)
        #expect(unionRect.width == 270) // max X = 280, min X = 10, 280-10 = 270
        #expect(unionRect.height == 80) // max Y = 100, min Y = 20, 100-20 = 80

        let intersectRect = r1.intersection(r2)
        #expect(intersectRect.isEmpty == true)
    }
}
