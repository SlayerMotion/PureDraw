import Core
import Geometry
import Testing

/// `Path.strokedOutline`: the CG-native stroke-to-fill (`CGContextReplacePathWithStrokedPath` /
/// `CGPath.copy(strokingWithWidth:…)`). Tests the outline geometry directly via `contains`.
@Suite("Stroke outline")
struct StrokeOutlineTests {
    @Test func strokedOutlineOfALineIsACoveringBand() {
        var path = Path()
        path.move(to: Point(x: 10, y: 50))
        path.addLine(to: Point(x: 90, y: 50))

        let butt = path.strokedOutline(lineWidth: 20, lineCap: .butt)
        #expect(butt.contains(Point(x: 50, y: 45))) // inside the 20-wide band
        #expect(butt.contains(Point(x: 50, y: 55)))
        #expect(!butt.contains(Point(x: 50, y: 30))) // above the band
        #expect(!butt.contains(Point(x: 4, y: 50))) // butt cap does not extend past the end

        let round = path.strokedOutline(lineWidth: 20, lineCap: .round)
        #expect(round.contains(Point(x: 4, y: 50))) // round cap extends ~halfW past the end
    }

    @Test func dashedStrokeOutlineHasGaps() {
        var path = Path()
        path.move(to: Point(x: 0, y: 10))
        path.addLine(to: Point(x: 100, y: 10))
        // 10-on / 10-off from x=0: x in [0,10] painted, [10,20] gap, [20,30] painted, ...
        let dashed = path.strokedOutline(lineWidth: 6, lineCap: .butt, dashLengths: [10, 10])
        #expect(dashed.contains(Point(x: 5, y: 10))) // first "on" run
        #expect(!dashed.contains(Point(x: 15, y: 10))) // the gap
        #expect(dashed.contains(Point(x: 25, y: 10))) // next "on" run
    }
}
