//
//  LessonVideoTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
import Renderers
import Testing

struct LessonVideoTests {
    @Test func renderLesson4BezierVideo() throws {
        let width = 480
        let height = 320
        let totalFrames = 90
        let fps = 30.0

        // Load system font for labeling
        let fontUrl = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf")
        let font = try? Font(provider: DataProvider(data: Array(Data(contentsOf: fontUrl))))

        var frames: [Image] = []
        frames.reserveCapacity(totalFrames)

        for i in 0 ..< totalFrames {
            var context = GraphicsContext()
            let t = Double(i) / Double(totalFrames)

            // 1. Draw dark background slate
            context.setFillColor(Color(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0))
            context.fill(Rect(x: 0, y: 0, width: Double(width), height: Double(height)))

            // 2. Draw coordinate grid lines
            context.setStrokeColor(Color(red: 0.12, green: 0.12, blue: 0.18, alpha: 0.4))
            context.setLineWidth(1.0)

            let gridSpacing = 30.0
            for x in stride(from: 0.0, through: Double(width), by: gridSpacing) {
                context.move(to: Point(x: x, y: 0))
                context.addLine(to: Point(x: x, y: Double(height)))
                context.strokePath()
            }
            for y in stride(from: 0.0, through: Double(height), by: gridSpacing) {
                context.move(to: Point(x: 0, y: y))
                context.addLine(to: Point(x: Double(width), y: y))
                context.strokePath()
            }

            // 3. Compute control points
            let p0 = Point(x: 60.0, y: 140.0)
            let p3 = Point(x: 420.0, y: 140.0)

            // Orbiting control points to dynamically morph the curve
            let theta1 = 2.0 * Double.pi * t
            let theta2 = -2.0 * Double.pi * t + Double.pi

            let p1 = Point(x: 150.0 + 60.0 * cos(theta1), y: 160.0 + 60.0 * sin(theta1))
            let p2 = Point(x: 330.0 + 60.0 * cos(theta2), y: 160.0 + 60.0 * sin(theta2))

            // 4. Draw control polygon (dashed lines connecting control points)
            context.saveGState()
            context.setStrokeColor(Color(red: 0.5, green: 0.5, blue: 0.6, alpha: 0.5))
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0.0, lengths: [5.0, 5.0])
            context.move(to: p0)
            context.addLine(to: p1)
            context.addLine(to: p2)
            context.addLine(to: p3)
            context.strokePath()
            context.restoreGState()

            // 5. Draw the cubic Bezier curve (solid neon cyan line)
            context.saveGState()
            context.setStrokeColor(Color(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0))
            context.setLineWidth(4.0)
            context.move(to: p0)
            context.addCurve(to: p3, control1: p1, control2: p2)
            context.strokePath()
            context.restoreGState()

            // 6. Draw control point markers (circles with white borders)
            let drawMarker: (Point, Color) -> Void = { point, color in
                context.setFillColor(color)
                context.fillEllipse(in: Rect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
                context.setStrokeColor(Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
                context.setLineWidth(1.5)
                context.strokeEllipse(in: Rect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
            }

            drawMarker(p0, Color(red: 0.2, green: 0.8, blue: 0.3, alpha: 1.0)) // Green anchor
            drawMarker(p3, Color(red: 0.2, green: 0.8, blue: 0.3, alpha: 1.0)) // Green anchor
            drawMarker(p1, Color(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)) // Orange control
            drawMarker(p2, Color(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)) // Orange control

            // 7. Render text labels
            if let f = font {
                context.saveGState()
                context.setFont(f)
                context.setFillColor(Color(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.95))

                // Title
                context.setFontSize(14.0)
                context.showText("Lesson 4: Bezier Curve & Subdivision", at: Point(x: 20.0, y: 285.0))

                // Equations
                context.setFontSize(9.0)
                context.setFillColor(Color(red: 0.6, green: 0.6, blue: 0.7, alpha: 0.8))
                context.showText("B(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃", at: Point(x: 20.0, y: 268.0))

                // Labels
                context.setFontSize(11.0)
                context.setFillColor(Color(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.9))
                context.showText("P0 (Anchor)", at: Point(x: p0.x - 25.0, y: p0.y - 20.0))
                context.showText("P3 (Anchor)", at: Point(x: p3.x - 25.0, y: p3.y - 20.0))
                context.showText("P1 (Control)", at: Point(x: p1.x - 28.0, y: p1.y + 15.0))
                context.showText("P2 (Control)", at: Point(x: p2.x - 28.0, y: p2.y + 15.0))

                context.restoreGState()
            }

            // 8. Render frame to image
            let image = try BitmapRenderer(width: width, height: height).draw(context)
            frames.append(image)
        }

        // 9. Encode and write the animated PNG file
        let pngData = PNGEncoder.encodeAnimated(frames, frameDelay: 1.0 / fps)
        let dir = URL(fileURLWithPath: "/tmp/pl_demo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let outputFile = dir.appendingPathComponent("lesson4_bezier.png")
        try Data(pngData).write(to: outputFile)

        #expect(FileManager.default.fileExists(atPath: outputFile.path))
    }
}
