//
//  EdgeAwareOracleTests.swift
//  PureDraw
//
//  An edge-aware check on the ORACLE's geometric faithfulness. A whole-image mean-absolute
//  tolerance (how parity suites compare renders) passes three real bugs it cannot localise:
//  a uniform colour/gamma bias (every pixel off by a constant), a sub-pixel shift (the bulk
//  is unchanged, only the boundary moves), and a dropped thin feature. Because every backend
//  is gated against BitmapRenderer, a fault here is inherited invisibly. So assert against the
//  ANALYTIC rectangle instead of a tolerance: interior pixels exactly the fill (zero
//  tolerance), exterior pixels exactly empty, and the inked area + centroid equal the
//  rectangle's, and the area/centroid catch a shift or scale that interior-exactness alone would
//  miss.
//

@testable import Core
import Geometry
@testable import Renderers
import Testing

struct EdgeAwareOracleTests {
    @Test func filledRectIsInteriorExactAndGeometricallyFaithful() throws {
        let width = 40, height = 40
        // Integer-aligned, so pixel-centre sampling gives full coverage with no edge AA: the
        // covered area and centroid are exact, not approximate.
        let rect = Rect(x: 10, y: 10, width: 20, height: 20) // centre (20,20), area 400
        var context = GraphicsContext()
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(rect)
        let image = try BitmapRenderer(width: width, height: height).draw(context)

        // (1) Interior is EXACTLY the fill (zero tolerance, ~1/255). Catches a colour/gamma
        // bias that a mean-tolerance check would absorb.
        for (x, y) in [(15, 15), (20, 20), (25, 25), (12, 27), (27, 12)] {
            let p = image.pixelColor(x: x, y: y)
            #expect(
                abs(p.red - 1) < 0.004 && p.green < 0.004 && p.blue < 0.004 && p.alpha > 0.996,
                "interior (\(x),\(y)) must be exactly the fill; got \(p)"
            )
        }
        // (2) Exterior is EXACTLY empty.
        for (x, y) in [(2, 2), (37, 37), (5, 35), (35, 5)] {
            #expect(image.pixelColor(x: x, y: y).alpha < 0.004, "exterior (\(x),\(y)) must be empty")
        }
        // (3) Inked area + centroid equal the analytic rectangle. A sub-pixel shift leaves the
        // interior/exterior unchanged but moves the centroid; a scale error or dropped edge
        // changes the area. Centroid uses pixel CENTRES (x + 0.5).
        var area = 0.0, cx = 0.0, cy = 0.0
        for y in 0 ..< height {
            for x in 0 ..< width {
                let coverage = image.pixelColor(x: x, y: y).alpha
                area += coverage
                cx += coverage * (Double(x) + 0.5)
                cy += coverage * (Double(y) + 0.5)
            }
        }
        cx /= area
        cy /= area
        #expect(abs(area - 400) < 1, "covered area must equal the 20x20 rect (400); got \(area)")
        #expect(
            abs(cx - 20) < 0.1 && abs(cy - 20) < 0.1,
            "ink centroid must be the rect centre (20,20); got (\(cx),\(cy)) -- a sub-pixel shift moves this where a mean-tolerance check would not notice"
        )
    }
}
