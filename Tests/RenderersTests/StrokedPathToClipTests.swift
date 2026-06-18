//
//  StrokedPathToClipTests.swift
//  PureDraw
//
//  GraphicsContext.replacePathWithStrokedPath turns the current path into the fillable outline
//  of its stroke (mirroring CGContextReplacePathWithStrokedPath), which is the infrastructure a
//  gradient-painted stroke needs: stroke -> outline -> clip -> drawGradient (PureDraw #119, split
//  from PureComposition #98). Verifies the outline IS the stroke, and that a gradient then fills
//  only the stroke region.
//

import Core
import Geometry
import Renderers
import Testing

struct StrokedPathToClipTests {
    private let w = 80
    private let h = 80

    private func alpha(_ image: Image, _ x: Int, _ y: Int) -> Int {
        Int(image.data[(y * w + x) * 4 + 3])
    }

    private func meanAbsDiff(_ a: Image, _ b: Image) -> Double {
        guard a.data.count == b.data.count, !a.data.isEmpty else { return .infinity }
        var sum = 0.0
        for i in a.data.indices {
            sum += abs(Double(a.data[i]) - Double(b.data[i]))
        }
        return sum / Double(a.data.count)
    }

    @Test func strokedOutlineFillEqualsStroke() throws {
        // Filling the stroked outline must produce the same pixels as stroking the path:
        // replacePathWithStrokedPath + fillPath == strokePath, for the same width and colour.
        let color = Color(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
        func path(into c: inout GraphicsContext) {
            c.move(to: Point(x: 12, y: 14))
            c.addLine(to: Point(x: 66, y: 30))
            c.addLine(to: Point(x: 20, y: 64))
        }

        var stroked = GraphicsContext()
        stroked.setStrokeColor(color)
        stroked.setLineWidth(9)
        path(into: &stroked)
        stroked.strokePath()
        let strokeImage = try BitmapRenderer(width: w, height: h).render(stroked)

        var outlined = GraphicsContext()
        outlined.setLineWidth(9)
        path(into: &outlined)
        outlined.replacePathWithStrokedPath()
        outlined.setFillColor(color)
        outlined.fillPath()
        let outlineImage = try BitmapRenderer(width: w, height: h).render(outlined)

        #expect(meanAbsDiff(strokeImage, outlineImage) < 1.0, "filling the stroked outline must match stroking the path")
    }

    @Test func gradientFillsOnlyTheStrokeRegion() throws {
        // The #119 use case: paint a stroke with a gradient by clipping to its outline. The
        // gradient must appear within the stroke band and nowhere else.
        var c = GraphicsContext()
        c.setLineWidth(12)
        c.move(to: Point(x: 0, y: 40))
        c.addLine(to: Point(x: 80, y: 40)) // horizontal line, stroke band y in [34, 46]
        c.replacePathWithStrokedPath()
        c.clip()
        let gradient = Gradient(stops: [GradientStop(color: .white, location: 0), GradientStop(color: .white, location: 1)])
        c.drawLinearGradient(gradient, start: Point(x: 0, y: 0), end: Point(x: 80, y: 0))
        let image = try BitmapRenderer(width: w, height: h).render(c)

        #expect(alpha(image, 40, 40) > 0, "the gradient must fill the centre of the stroke band")
        #expect(alpha(image, 40, 5) == 0, "the gradient must not paint outside the stroke band (clipped away)")
    }
}
