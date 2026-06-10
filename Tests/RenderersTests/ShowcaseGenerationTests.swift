//
//  ShowcaseGenerationTests.swift
//  PureDraw
//
//  Generates a poster PDF demonstrating PureDraw's capabilities. Run with
//  `swift test --filter generateShowcasePDF`; the PDF is written to the user's
//  Downloads folder.
//

import Core
import Foundation
import Geometry
@testable import Renderers
import Testing

struct ShowcaseGenerationTests {
    @Test func generateShowcasePDF() throws {
        let width = 612.0
        let height = 850.0
        var ctx = GraphicsContext()

        // Labels are disabled: Font.glyphIndex mis-maps multi-segment cmaps in
        // real system fonts (tracked separately), so the poster stays wordless
        // rather than rendering .notdef boxes. Set a font here once that is
        // fixed to bring the labels back.
        let font: Font? = nil

        drawBackground(&ctx, width: width, height: height)
        drawTitle(&ctx, font: font, width: width)
        drawCornerShowcase(&ctx, font: font, originY: 96)
        drawGradientAndBlend(&ctx, font: font, originY: 270)
        drawShadowTransparency(&ctx, font: font, originY: 270)
        drawCrumple(&ctx, font: font, originY: 452)
        drawPerspective(&ctx, font: font, originY: 452)
        drawScarf(&ctx, font: font, originY: 648)
        drawFooter(&ctx, font: font, width: width, height: height)

        let data = try PDFRenderer(width: width, height: height).render(ctx)
        #expect(data.count > 1000)

        // Write to Downloads when it exists (a developer machine), otherwise to
        // the temp directory, so this stays safe on CI.
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let directory = FileManager.default.fileExists(atPath: downloads.path) ? downloads : FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("PureDraw-Showcase.pdf")
        try data.write(to: url)
        print("Showcase PDF written to \(url.path)")
    }

    // MARK: - Sections

    private func drawBackground(_ ctx: inout GraphicsContext, width: Double, height: Double) {
        ctx.saveGState()
        ctx.addRect(Rect(x: 0, y: 0, width: width, height: height))
        ctx.clip()
        let sky = Gradient(stops: [
            GradientStop(color: Color(red: 0.06, green: 0.07, blue: 0.12), location: 0),
            GradientStop(color: Color(red: 0.10, green: 0.12, blue: 0.20), location: 1),
        ])
        ctx.drawLinearGradient(sky, start: Point(x: 0, y: 0), end: Point(x: 0, y: height))
        ctx.restoreGState()
    }

    private func drawTitle(_ ctx: inout GraphicsContext, font: Font?, width _: Double) {
        guard let font else { return }
        ctx.setFont(font)
        ctx.setFontSize(34)
        ctx.setFillColor(.white)
        ctx.showText("PUREDRAW", at: Point(x: 40, y: 56))
        ctx.setFontSize(13)
        ctx.setFillColor(Color(red: 0.55, green: 0.6, blue: 0.75))
        ctx.showText("dependency-free swift 2d graphics", at: Point(x: 42, y: 78))
    }

    /// Circular vs tunable-continuous vs exact-Apple corners, each gradient
    /// filled with a soft drop shadow.
    private func drawCornerShowcase(_ ctx: inout GraphicsContext, font: Font?, originY: Double) {
        label(&ctx, font: font, "CORNERS  circular / continuous / apple-exact", x: 40, y: originY)
        let tile = Rect(x: 0, y: 0, width: 150, height: 130)
        let radius = 46.0
        let labels = ["circular", "continuous", "apple"]
        for index in 0 ..< 3 {
            let ox = 40 + Double(index) * 178
            let oy = originY + 14
            var shape = Path()
            let box = Rect(x: ox, y: oy, width: tile.width, height: tile.height)
            switch index {
            case 0: shape.addRoundedRect(in: box, cornerWidth: radius, cornerHeight: radius)
            case 1: shape.addContinuousRoundedRect(in: box, cornerRadius: radius, smoothing: 0.6)
            default: shape.addAppleRoundedRect(in: box, cornerRadius: radius)
            }

            // Skew the middle tile into a parallelogram (an affine shear about
            // its vertical center), so the row is not three identical squares.
            if index == 1 {
                let cy = oy + tile.height / 2
                let k = 0.34
                shape = shape.applying(Geometry.AffineTransform(a: 1, b: 0, c: k, d: 1, tx: -k * cy, ty: 0))
            }

            ctx.saveGState()
            ctx.setShadow(offset: Point(x: 0, y: 8), blur: 14, color: Color(red: 0, green: 0, blue: 0, alpha: 0.55))
            ctx.addPath(shape)
            ctx.clip()
            let grad = Gradient(stops: [
                GradientStop(color: tileColor(index, 0), location: 0),
                GradientStop(color: tileColor(index, 1), location: 1),
            ])
            ctx.drawLinearGradient(grad, start: Point(x: ox, y: oy), end: Point(x: ox + tile.width, y: oy + tile.height))
            ctx.restoreGState()
            smallLabel(&ctx, font: font, labels[index], x: ox + 8, y: oy + tile.height + 16)
        }
    }

    /// Linear, radial, and a function-sampled rainbow gradient with multiply
    /// blending in a transparency layer.
    private func drawGradientAndBlend(_ ctx: inout GraphicsContext, font: Font?, originY: Double) {
        label(&ctx, font: font, "GRADIENTS + BLEND", x: 40, y: originY)
        let panel = Rect(x: 40, y: originY + 14, width: 240, height: 150)
        ctx.saveGState()
        var clip = Path()
        clip.addContinuousRoundedRect(in: panel, cornerRadius: 24, smoothing: 0.6)
        ctx.addPath(clip)
        ctx.clip()

        let rainbow = Gradient(samples: 64) { t in
            Color(red: 0.5 + 0.5 * cos(2 * .pi * t), green: 0.5 + 0.5 * cos(2 * .pi * t + 2), blue: 0.5 + 0.5 * cos(2 * .pi * t + 4))
        }
        ctx.drawLinearGradient(rainbow, start: Point(x: panel.minX, y: panel.minY), end: Point(x: panel.maxX, y: panel.minY))

        ctx.setBlendMode(.multiply)
        for i in 0 ..< 3 {
            let radial = Gradient(stops: [
                GradientStop(color: Color(red: 1, green: 1, blue: 1, alpha: 0.9), location: 0),
                GradientStop(color: Color(red: 0.1, green: 0.1, blue: 0.3, alpha: 0), location: 1),
            ])
            let c = Point(x: panel.minX + 60 + Double(i) * 60, y: panel.minY + 75)
            ctx.drawRadialGradient(radial, startCenter: c, startRadius: 0, endCenter: c, endRadius: 55)
        }
        ctx.restoreGState()
    }

    /// Overlapping translucent discs with soft, semi-transparent drop shadows.
    private func drawShadowTransparency(_ ctx: inout GraphicsContext, font: Font?, originY: Double) {
        label(&ctx, font: font, "SHADOWS + TRANSPARENCY", x: 320, y: originY)
        let colors = [
            Color(red: 0.96, green: 0.30, blue: 0.42, alpha: 0.72),
            Color(red: 0.25, green: 0.74, blue: 0.96, alpha: 0.72),
            Color(red: 0.99, green: 0.80, blue: 0.22, alpha: 0.72),
        ]
        for (i, color) in colors.enumerated() {
            ctx.saveGState()
            ctx.setShadow(offset: Point(x: 4, y: 10), blur: 16, color: Color(red: 0, green: 0, blue: 0, alpha: 0.5))
            ctx.setFillColor(color)
            let c = Rect(x: 330 + Double(i) * 46, y: originY + 30 + Double(i % 2) * 30, width: 92, height: 92)
            ctx.addEllipse(in: c)
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    /// A gradient panel with a grid, crumpled by the non-linear deformer.
    private func drawCrumple(_ ctx: inout GraphicsContext, font: Font?, originY: Double) {
        label(&ctx, font: font, "CRUMPLE  (non-linear deformer)", x: 40, y: originY)
        let panel = Rect(x: 40, y: originY + 14, width: 240, height: 150)
        let crumple = CrumpleDeformer(center: Point(x: panel.midX, y: panel.midY), radius: 95, pinchStrength: 0.4, wrinkleStrength: 1.0)

        // Crumpled gradient fill.
        ctx.saveGState()
        var face = Path()
        face.addRect(panel)
        let crumpled = face.subdivided(maxSegmentLength: 4).deforming { crumple.transform($0) }
        ctx.addPath(crumpled)
        ctx.clip()
        let paper = Gradient(stops: [
            GradientStop(color: Color(red: 0.95, green: 0.55, blue: 0.30), location: 0),
            GradientStop(color: Color(red: 0.55, green: 0.18, blue: 0.45), location: 1),
        ])
        ctx.drawLinearGradient(paper, start: Point(x: panel.minX, y: panel.minY), end: Point(x: panel.maxX, y: panel.maxY))
        ctx.restoreGState()

        // Crumpled grid lines on top.
        ctx.setStrokeColor(Color(red: 1, green: 1, blue: 1, alpha: 0.28))
        ctx.setLineWidth(1)
        for gx in stride(from: panel.minX, through: panel.maxX, by: 20) {
            var line = Path()
            line.move(to: Point(x: gx, y: panel.minY))
            line.addLine(to: Point(x: gx, y: panel.maxY))
            ctx.addPath(line.subdivided(maxSegmentLength: 4).deforming { crumple.transform($0) })
            ctx.strokePath()
        }
        for gy in stride(from: panel.minY, through: panel.maxY, by: 20) {
            var line = Path()
            line.move(to: Point(x: panel.minX, y: gy))
            line.addLine(to: Point(x: panel.maxX, y: gy))
            ctx.addPath(line.subdivided(maxSegmentLength: 4).deforming { crumple.transform($0) })
            ctx.strokePath()
        }
    }

    /// A rotated, depth-sorted, per-face-lit 3D cube built from projected
    /// A translucent, depth-sorted 3D cube with a projective grid-and-circles
    /// texture on its front face. Ported from PureDraw's 3D perspective scene.
    private func drawPerspective(_ ctx: inout GraphicsContext, font: Font?, originY: Double) {
        label(&ctx, font: font, "3D CUBE  (translucent + projective)", x: 320, y: originY)
        let center = Point(x: 452, y: originY + 96)
        let half = 60.0
        let camera = 300.0
        let translateZ = 200.0
        let scale = 0.95
        let rotY = 0.52
        let rotX = 0.35

        // Eight corners, rotated, translated, then projected and scaled into
        // the section around `center`.
        let unit: [(Double, Double, Double)] = [
            (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
            (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),
        ]
        func world(_ p: (Double, Double, Double)) -> (Double, Double, Double) {
            var (x, y, z) = (p.0 * half, p.1 * half, p.2 * half)
            (x, z) = (x * cos(rotY) - z * sin(rotY), x * sin(rotY) + z * cos(rotY))
            (y, z) = (y * cos(rotX) - z * sin(rotX), y * sin(rotX) + z * cos(rotX))
            return (x, y, z + translateZ)
        }
        func project(_ p: (Double, Double, Double)) -> Point {
            let f = camera / (p.2 + camera)
            return Point(x: center.x + p.0 * f * scale, y: center.y + p.1 * f * scale)
        }
        let verts = unit.map(world)
        let screen = verts.map(project)

        struct Face { let idx: [Int]
            let color: Color
        }
        let faces = [
            Face(idx: [0, 1, 2, 3], color: Color(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.7)),
            Face(idx: [5, 4, 7, 6], color: Color(red: 0.2, green: 0.9, blue: 0.2, alpha: 0.7)),
            Face(idx: [4, 5, 1, 0], color: Color(red: 0.2, green: 0.2, blue: 0.9, alpha: 0.7)),
            Face(idx: [3, 2, 6, 7], color: Color(red: 0.9, green: 0.9, blue: 0.2, alpha: 0.7)),
            Face(idx: [4, 0, 3, 7], color: Color(red: 0.9, green: 0.2, blue: 0.9, alpha: 0.7)),
            Face(idx: [1, 5, 6, 2], color: Color(red: 0.2, green: 0.9, blue: 0.9, alpha: 0.7)),
        ]
        let ordered = faces.sorted {
            $0.idx.map { verts[$0].2 }.reduce(0, +) > $1.idx.map { verts[$0].2 }.reduce(0, +)
        }

        for face in ordered {
            func poly() -> Path {
                var p = Path()
                p.move(to: screen[face.idx[0]])
                for i in 1 ..< 4 {
                    p.addLine(to: screen[face.idx[i]])
                }
                p.closeSubpath()
                return p
            }
            ctx.setFillColor(face.color)
            ctx.addPath(poly())
            ctx.fillPath()
            // Round joins so the edge strokes never spike past the corners.
            ctx.setStrokeColor(Color(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.setLineWidth(1.5)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.addPath(poly())
            ctx.strokePath()

            // Projective grid + circles on the front face shows 2D geometry
            // distorted into perspective.
            if face.idx == [0, 1, 2, 3] {
                let faceRect = Rect(x: -half, y: -half, width: 2 * half, height: 2 * half)
                let t = ProjectiveTransform.rectToQuad(
                    faceRect,
                    p0: screen[0], p1: screen[1], p2: screen[2], p3: screen[3]
                )
                ctx.saveGState()
                ctx.setStrokeColor(Color(red: 1, green: 1, blue: 1, alpha: 0.85))
                ctx.setLineWidth(1.0)
                var grid = Path()
                for u in stride(from: -0.6, through: 0.6, by: 0.3) {
                    grid.move(to: Point(x: u * half, y: -half))
                    grid.addLine(to: Point(x: u * half, y: half))
                    grid.move(to: Point(x: -half, y: u * half))
                    grid.addLine(to: Point(x: half, y: u * half))
                }
                ctx.addPath(grid.applying(t))
                ctx.strokePath()
                var circles = Path()
                for rf in [0.3, 0.65] {
                    circles.addEllipse(in: Rect(x: -rf * half, y: -rf * half, width: 2 * rf * half, height: 2 * rf * half))
                }
                ctx.addPath(circles.applying(t))
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
    }

    /// A flowing scarf: overlapping wavy translucent bands in Apple system
    /// colors, each with a gradient sheen and a soft drop shadow, so the
    /// overlaps blend like draped fabric.
    private func drawScarf(_ ctx: inout GraphicsContext, font: Font?, originY: Double) {
        label(&ctx, font: font, "SCARF  (curves + transparency + shadows)", x: 40, y: originY)
        let left = 56.0
        let right = 556.0
        let bandHeight = 30.0
        // Apple system colors.
        let bands: [(y: Double, amp: Double, phase: Double, color: Color)] = [
            (originY + 34, 14, 0.0, Color(red: 1.00, green: 0.18, blue: 0.33)), // systemPink
            (originY + 48, 16, 1.1, Color(red: 1.00, green: 0.58, blue: 0.00)), // systemOrange
            (originY + 62, 13, 2.3, Color(red: 0.35, green: 0.34, blue: 0.84)), // systemIndigo
            (originY + 76, 15, 3.4, Color(red: 0.19, green: 0.69, blue: 0.78)), // systemTeal
        ]
        let freq = 2.0 * .pi / 210.0
        for band in bands {
            func wave(_ x: Double, _ offset: Double) -> Double {
                band.y + offset + band.amp * sin(freq * x + band.phase)
            }
            var path = Path()
            let steps = 80
            path.move(to: Point(x: left, y: wave(left, 0)))
            for i in 1 ... steps {
                let x = left + (right - left) * Double(i) / Double(steps)
                path.addLine(to: Point(x: x, y: wave(x, 0)))
            }
            for i in stride(from: steps, through: 0, by: -1) {
                let x = left + (right - left) * Double(i) / Double(steps)
                path.addLine(to: Point(x: x, y: wave(x, bandHeight)))
            }
            path.closeSubpath()

            // Soft drop shadow, then a translucent gradient-sheened fill.
            ctx.saveGState()
            ctx.setShadow(offset: Point(x: 0, y: 7), blur: 12, color: Color(red: 0, green: 0, blue: 0, alpha: 0.45))
            ctx.addPath(path)
            ctx.clip()
            let sheen = Gradient(stops: [
                GradientStop(color: shade(band.color, 1.15, alpha: 0.78), location: 0),
                GradientStop(color: shade(band.color, 0.65, alpha: 0.78), location: 1),
            ])
            ctx.drawLinearGradient(sheen, start: Point(x: left, y: band.y), end: Point(x: left, y: band.y + bandHeight))
            ctx.restoreGState()
        }
    }

    private func shade(_ c: Color, _ k: Double, alpha: Double) -> Color {
        Color(red: min(1, c.red * k), green: min(1, c.green * k), blue: min(1, c.blue * k), alpha: alpha)
    }

    private func drawFooter(_ ctx: inout GraphicsContext, font: Font?, width _: Double, height: Double) {
        guard let font else { return }
        ctx.setFont(font)
        ctx.setFontSize(10)
        ctx.setFillColor(Color(red: 0.5, green: 0.55, blue: 0.7))
        ctx.showText("rendered by puredraw to vector pdf", at: Point(x: 40, y: height - 28))
    }

    // MARK: - Helpers

    private func tileColor(_ index: Int, _ end: Int) -> Color {
        let palette: [[Color]] = [
            [Color(red: 0.40, green: 0.50, blue: 0.95), Color(red: 0.20, green: 0.28, blue: 0.65)],
            [Color(red: 0.95, green: 0.45, blue: 0.65), Color(red: 0.60, green: 0.20, blue: 0.55)],
            [Color(red: 0.30, green: 0.85, blue: 0.70), Color(red: 0.15, green: 0.55, blue: 0.55)],
        ]
        return palette[index][end]
    }

    private func label(_ ctx: inout GraphicsContext, font: Font?, _ text: String, x: Double, y: Double) {
        guard let font else { return }
        ctx.setFont(font)
        ctx.setFontSize(11)
        ctx.setFillColor(Color(red: 0.8, green: 0.84, blue: 0.95))
        ctx.showText(text, at: Point(x: x, y: y))
    }

    private func smallLabel(_ ctx: inout GraphicsContext, font: Font?, _ text: String, x: Double, y: Double) {
        guard let font else { return }
        ctx.setFont(font)
        ctx.setFontSize(9)
        ctx.setFillColor(Color(red: 0.6, green: 0.65, blue: 0.8))
        ctx.showText(text, at: Point(x: x, y: y))
    }
}
