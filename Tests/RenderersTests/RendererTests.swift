//
//  RendererTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
import Renderers
import Testing
import Validation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

struct RendererTests {
    @Test func svgRendererOutputStructure() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 1.0, green: 0.0, blue: 0.0)) // Red
        context.setStrokeColor(Color(red: 0.0, green: 0.0, blue: 1.0)) // Blue
        context.setLineWidth(4.0)

        // Draw a rect
        context.addRect(Rect(x: 10, y: 15, width: 100, height: 200))
        context.fillPath()

        // Draw a line
        context.move(to: Point(x: 0, y: 0))
        context.addLine(to: Point(x: 50, y: 50))
        context.strokePath()

        // Render SVG
        let svg = try SVGRenderer().render(context)

        // Verify XML structure
        #expect(svg.hasPrefix("<svg"))
        #expect(svg.hasSuffix("</svg>"))

        // Verify shapes and properties are present
        #expect(svg.contains("width=\"110.0\"")) // Dynamic viewport calculations
        #expect(svg.contains("height=\"215.0\""))
        #expect(svg.contains("fill=\"#FF0000\"")) // Red fill hex
        #expect(svg.contains("stroke=\"#0000FF\"")) // Blue stroke hex
        #expect(svg.contains("stroke-width=\"4.0\"")) // Stroke width
        #expect(svg.contains("M 10.0 15.0 L 110.0 15.0")) // Path syntax
    }

    @Test func svgRendererClipping() throws {
        var context = GraphicsContext()

        // Define clipping path
        context.move(to: Point(x: 0, y: 0))
        context.addLine(to: Point(x: 50, y: 0))
        context.addLine(to: Point(x: 50, y: 50))
        context.closeSubpath()
        context.clip()

        // Draw shape affected by clip
        context.addRect(Rect(x: 0, y: 0, width: 100, height: 100))
        context.fillPath()

        let svg = try SVGRenderer().render(context)

        #expect(svg.contains("<clipPath id=\"clip-0\">"))
        #expect(svg.contains("clip-path=\"url(#clip-0)\""))
    }

    @Test func coreGraphicsRendererExecution() throws {
        #if canImport(CoreGraphics)
            // 1. Setup offscreen CGContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let cgContext = CGContext(
                data: nil,
                width: 100,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                Issue.record("Failed to create offscreen CGContext")
                return
            }

            // 2. Setup drawing commands
            var context = GraphicsContext()
            context.translate(by: 10, 10)
            context.scale(by: 2, 2)
            context.setAlpha(0.8)

            // Clipping
            context.move(to: Point(x: 0, y: 0))
            context.addLine(to: Point(x: 20, y: 20))
            context.clip()

            // Fill
            context.setFillColor(.white)
            context.addRect(Rect(x: 0, y: 0, width: 50, height: 50))
            context.fillPath()

            // Stroke
            context.setStrokeColor(.black)
            context.setLineWidth(2.0)
            context.setLineCap(.round)
            context.setLineJoin(.bevel)
            context.setLineDash(phase: 1.0, lengths: [4.0, 2.0])
            context.move(to: Point(x: 0, y: 0))
            context.addLine(to: Point(x: 40, y: 40))
            context.strokePath()

            // 3. Render and assert no crashes/errors
            let renderer = CoreGraphicsRenderer(context: cgContext)
            #expect(throws: Never.self) {
                try renderer.render(context)
            }
        #else
            // Skip on non-Apple platforms
        #endif
    }

    @Test func pdfRendererOutputStructure() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 1.0, green: 0.0, blue: 0.0)) // Red
        context.setStrokeColor(Color(red: 0.0, green: 0.0, blue: 1.0)) // Blue
        context.setLineWidth(4.0)

        // Draw a rect
        context.addRect(Rect(x: 10, y: 15, width: 100, height: 200))
        context.fillPath()

        // Draw a line
        context.move(to: Point(x: 0, y: 0))
        context.addLine(to: Point(x: 50, y: 50))
        context.strokePath()

        // Render PDF
        let pdfData = try PDFRenderer(width: 500, height: 500).render(context)

        // Verify PDF Header and Footer
        let pdfString = String(data: pdfData, encoding: .ascii) ?? ""
        #expect(pdfString.hasPrefix("%PDF-1.4"))
        #expect(pdfString.contains("%%EOF"))
        #expect(pdfString.contains("/Type /Catalog"))
        #expect(pdfString.contains("/Type /Page"))
        #expect(pdfString.contains("stream"))
        #expect(pdfString.contains("endstream"))
    }

    @Test func svgAndCGRendererGradientsAndShadows() throws {
        var context = GraphicsContext()

        // Set Shadow
        context.setShadow(offset: Point(x: 5, y: 5), blur: 3.0, color: Color(red: 0, green: 0, blue: 0, alpha: 0.5))

        // Create Gradient
        let stops = [
            GradientStop(color: .white, location: 0.0),
            GradientStop(color: .black, location: 1.0),
        ]
        let grad = Gradient(stops: stops)

        // Draw linear gradient
        context.drawLinearGradient(grad, start: Point(x: 0, y: 0), end: Point(x: 100, y: 100))

        // Draw radial gradient
        context.drawRadialGradient(grad, startCenter: Point(x: 50, y: 50), startRadius: 0.0, endCenter: Point(x: 50, y: 50), endRadius: 50.0)

        // Render SVG and assert
        let svg = try SVGRenderer().render(context)
        #expect(svg.contains("<linearGradient id=\"grad-0\""))
        #expect(svg.contains("<radialGradient id=\"grad-1\""))
        #expect(svg.contains("<filter id=\"shadow-0\">"))
        #expect(svg.contains("filter=\"url(#shadow-0)\""))

        // Render PDF and assert
        let pdfData = try PDFRenderer().render(context)
        let pdfString = String(data: pdfData, encoding: .ascii) ?? ""
        #expect(pdfString.contains("/ShadingType 2")) // Linear Shading
        #expect(pdfString.contains("/ShadingType 3")) // Radial Shading

        #if canImport(CoreGraphics)
            // Render to CGContext and assert no throws
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let cgContext = CGContext(
                data: nil,
                width: 100,
                height: 100,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                let renderer = CoreGraphicsRenderer(context: cgContext)
                #expect(throws: Never.self) {
                    try renderer.render(context)
                }
            }
        #endif
    }

    @Test func postScriptRendererOutputStructure() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 1.0, green: 0.0, blue: 0.0)) // Red
        context.setStrokeColor(Color(red: 0.0, green: 0.0, blue: 1.0)) // Blue
        context.setLineWidth(4.0)

        // Draw a rect
        context.addRect(Rect(x: 10, y: 15, width: 100, height: 200))
        context.fillPath()

        // Draw a line
        context.move(to: Point(x: 0, y: 0))
        context.addLine(to: Point(x: 50, y: 50))
        context.strokePath()

        // Create Gradient
        let stops = [
            GradientStop(color: .white, location: 0.0),
            GradientStop(color: .black, location: 1.0),
        ]
        let grad = Gradient(stops: stops)
        context.drawLinearGradient(grad, start: Point(x: 0, y: 0), end: Point(x: 100, y: 100))

        // Render PostScript
        let ps = try PostScriptRenderer(width: 500, height: 500).render(context)

        // Verify EPS Headers and contents
        #expect(ps.contains("%!PS-Adobe-3.0 EPSF-3.0"))
        #expect(ps.contains("%%BoundingBox: 0 0 500 500"))
        #expect(ps.contains("moveto"))
        #expect(ps.contains("lineto"))
        #expect(ps.contains("fill"))
        #expect(ps.contains("stroke"))
        #expect(ps.contains("/ShadingType 2"))
        #expect(ps.contains("shfill"))
    }

    @Test func canvasRendererOutputStructure() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 1.0, green: 0.0, blue: 0.0)) // Red
        context.setStrokeColor(Color(red: 0.0, green: 0.0, blue: 1.0)) // Blue
        context.setLineWidth(4.0)

        // Draw a rect
        context.addRect(Rect(x: 10, y: 15, width: 100, height: 200))
        context.fillPath()

        // Draw a line
        context.move(to: Point(x: 0, y: 0))
        context.addLine(to: Point(x: 50, y: 50))
        context.strokePath()

        // Create Gradient
        let stops = [
            GradientStop(color: .white, location: 0.0),
            GradientStop(color: .black, location: 1.0),
        ]
        let grad = Gradient(stops: stops)
        context.drawLinearGradient(grad, start: Point(x: 0, y: 0), end: Point(x: 100, y: 100))

        // Render Canvas JS
        let renderer = CanvasRenderer(contextName: "ctx")
        let js = try renderer.render(context)

        // Verify Canvas JS commands
        #expect(js.contains("ctx.save();"))
        #expect(js.contains("ctx.restore();"))
        #expect(js.contains("ctx.fillStyle = 'rgba(255, 0, 0, 1.0)';"))
        #expect(js.contains("ctx.strokeStyle = 'rgba(0, 0, 255, 1.0)';"))
        #expect(js.contains("ctx.lineWidth = 4.0;"))
        #expect(js.contains("ctx.moveTo(0.0, 0.0);"))
        #expect(js.contains("ctx.lineTo(50.0, 50.0);"))
        #expect(js.contains("ctx.createLinearGradient(0.0, 0.0, 100.0, 100.0)"))
        #expect(js.contains("ctx.fillRect(-10000, -10000, 20000, 20000);"))

        // Render complete HTML page
        let html = try renderer.renderToHTMLPage(context, width: 500, height: 500)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<canvas id=\"pureDrawCanvas\" width=\"500.0\" height=\"500.0\"></canvas>"))
        #expect(html.contains("ctx.save();"))
    }

    @Test func generate3DPerspectivePDF() throws {
        struct Point3D {
            var x: Double
            var y: Double
            var z: Double

            func rotatedY(_ angle: Double) -> Point3D {
                let cosA = cos(angle)
                let sinA = sin(angle)
                return Point3D(
                    x: x * cosA - z * sinA,
                    y: y,
                    z: x * sinA + z * cosA
                )
            }

            func rotatedX(_ angle: Double) -> Point3D {
                let cosA = cos(angle)
                let sinA = sin(angle)
                return Point3D(
                    x: x,
                    y: y * cosA - z * sinA,
                    z: y * sinA + z * cosA
                )
            }

            func translated(dx: Double, dy: Double, dz: Double) -> Point3D {
                Point3D(x: x + dx, y: y + dy, z: z + dz)
            }

            func projected(viewportSize: Double, cameraDistance: Double) -> Point {
                let factor = cameraDistance / (z + cameraDistance)
                let px = x * factor + viewportSize / 2.0
                let py = y * factor + viewportSize / 2.0
                return Point(x: px, y: py)
            }
        }

        var context = GraphicsContext()

        // 1. Background Gradient (Bright sky gradient so drop shadows are clearly visible)
        let bgStops = [
            GradientStop(color: Color(red: 0.75, green: 0.88, blue: 0.98), location: 0.0), // Light sky blue
            GradientStop(color: Color(red: 0.95, green: 0.95, blue: 0.98), location: 1.0), // Near-white
        ]
        context.drawLinearGradient(Gradient(stops: bgStops), start: Point(x: 0, y: 0), end: Point(x: 0, y: 500))

        // 2. Ground grid in 3D
        context.setStrokeColor(Color(red: 0.4, green: 0.4, blue: 0.8, alpha: 0.4))
        context.setLineWidth(1.0)

        let gridY: Double = 80

        // Lines parallel to Z axis
        for x in stride(from: -200.0, through: 200.0, by: 40.0) {
            let start3D = Point3D(x: x, y: gridY, z: 0)
            let end3D = Point3D(x: x, y: gridY, z: 400)

            let p1 = start3D.projected(viewportSize: 500, cameraDistance: 300)
            let p2 = end3D.projected(viewportSize: 500, cameraDistance: 300)

            context.move(to: p1)
            context.addLine(to: p2)
            context.strokePath()
        }

        // Lines parallel to X axis
        for z in stride(from: 0.0, through: 400.0, by: 40.0) {
            let start3D = Point3D(x: -200, y: gridY, z: z)
            let end3D = Point3D(x: 200, y: gridY, z: z)

            let p1 = start3D.projected(viewportSize: 500, cameraDistance: 300)
            let p2 = end3D.projected(viewportSize: 500, cameraDistance: 300)

            context.move(to: p1)
            context.addLine(to: p2)
            context.strokePath()
        }

        // 2b. Draw a skewed 2D badge in the sky (top-left)
        context.saveGState()
        context.translate(by: 40.0, 40.0)
        context.skew(by: 0.3, 0.0)

        // Draw badge background with shadow
        context.setShadow(offset: Point(x: 4, y: 4), blur: 4.0, color: Color(red: 0, green: 0, blue: 0, alpha: 0.45))
        context.setFillColor(Color(red: 0.9, green: 0.5, blue: 0.1, alpha: 0.85))
        context.addRoundedRect(in: Rect(x: 0, y: 0, width: 120, height: 40), cornerWidth: 5, cornerHeight: 5)
        context.fillPath()

        // Draw badge border without shadow
        context.clearShadow()
        context.setStrokeColor(.white)
        context.setLineWidth(2.0)
        context.addRoundedRect(in: Rect(x: 0, y: 0, width: 120, height: 40), cornerWidth: 5, cornerHeight: 5)
        context.strokePath()

        context.restoreGState()

        // 2c. Draw a perspective-distorted (homography-warped) 2D badge in the sky (top-right)
        // This simulates a true 3D camera distortion on 2D vectors
        let q0 = Point(x: 320.0, y: 50.0) // top-left
        let q1 = Point(x: 440.0, y: 35.0) // top-right (pulled up)
        let q2 = Point(x: 430.0, y: 95.0) // bottom-right (distorted down)
        let q3 = Point(x: 310.0, y: 75.0) // bottom-left

        let badgeRect = Rect(x: 0, y: 0, width: 120, height: 40)
        let badgeTransform = ProjectiveTransform.rectToQuad(badgeRect, p0: q0, p1: q1, p2: q2, p3: q3)

        var badgeBG = Path()
        badgeBG.addRoundedRect(in: badgeRect, cornerWidth: 5, cornerHeight: 5)
        let distortedBadgeBG = badgeBG.applying(badgeTransform)

        context.saveGState()
        // Cyan background with shadow
        context.setShadow(offset: Point(x: 4, y: 4), blur: 4.0, color: Color(red: 0, green: 0, blue: 0, alpha: 0.45))
        context.setFillColor(Color(red: 0.1, green: 0.7, blue: 0.9, alpha: 0.85))
        context.addPath(distortedBadgeBG)
        context.fillPath()

        // White border without shadow
        context.clearShadow()
        context.setStrokeColor(.white)
        context.setLineWidth(2.0)
        context.addPath(distortedBadgeBG)
        context.strokePath()
        context.restoreGState()

        // 3. 3D Cube sitting on grid
        let half: Double = 60
        let cubeVertices = [
            Point3D(x: -half, y: -half, z: -half), // 0
            Point3D(x: half, y: -half, z: -half), // 1
            Point3D(x: half, y: half, z: -half), // 2
            Point3D(x: -half, y: half, z: -half), // 3
            Point3D(x: -half, y: -half, z: half), // 4
            Point3D(x: half, y: -half, z: half), // 5
            Point3D(x: half, y: half, z: half), // 6
            Point3D(x: -half, y: half, z: half), // 7
        ]

        // Rotate and translate vertices
        let rotY = 0.52 // 30 degrees
        let rotX = 0.35 // 20 degrees
        let transX = 0.0
        let transY = -10.0
        let transZ = 200.0

        let transformedVertices = cubeVertices.map { v in
            v.rotatedY(rotY)
                .rotatedX(rotX)
                .translated(dx: transX, dy: transY, dz: transZ)
        }

        struct Face {
            let indices: [Int]
            let color: Color
        }

        let faces = [
            Face(indices: [0, 1, 2, 3], color: Color(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.7)), // Front (Red)
            Face(indices: [5, 4, 7, 6], color: Color(red: 0.2, green: 0.9, blue: 0.2, alpha: 0.7)), // Back (Green)
            Face(indices: [4, 5, 1, 0], color: Color(red: 0.2, green: 0.2, blue: 0.9, alpha: 0.7)), // Top (Blue)
            Face(indices: [3, 2, 6, 7], color: Color(red: 0.9, green: 0.9, blue: 0.2, alpha: 0.7)), // Bottom (Yellow)
            Face(indices: [4, 0, 3, 7], color: Color(red: 0.9, green: 0.2, blue: 0.9, alpha: 0.7)), // Left (Purple)
            Face(indices: [1, 5, 6, 2], color: Color(red: 0.2, green: 0.9, blue: 0.9, alpha: 0.7)), // Right (Cyan)
        ]

        // Sort faces by depth (painter's algorithm)
        let sortedFaces = faces.map { face -> (Face, Double) in
            let avgZ = face.indices.map { transformedVertices[$0].z }.reduce(0.0, +) / 4.0
            return (face, avgZ)
        }.sorted(by: { $0.1 > $1.1 }) // Draw further faces first

        // 3a. Draw a ground footprint shadow under the cube
        context.saveGState()
        context.setFillColor(Color(red: 0.05, green: 0.05, blue: 0.15, alpha: 0.5))

        var shadowVert3 = transformedVertices[3]
        var shadowVert2 = transformedVertices[2]
        var shadowVert6 = transformedVertices[6]
        var shadowVert7 = transformedVertices[7]

        shadowVert3.y = gridY
        shadowVert2.y = gridY
        shadowVert6.y = gridY
        shadowVert7.y = gridY

        let shadowStart = shadowVert3.projected(viewportSize: 500, cameraDistance: 300)
        context.move(to: shadowStart)
        context.addLine(to: shadowVert2.projected(viewportSize: 500, cameraDistance: 300))
        context.addLine(to: shadowVert6.projected(viewportSize: 500, cameraDistance: 300))
        context.addLine(to: shadowVert7.projected(viewportSize: 500, cameraDistance: 300))
        context.closeSubpath()
        context.fillPath()
        context.restoreGState()

        // 3b. Draw a floating 3D circle disk next to the cube (horizontal ring projected in perspective)
        context.saveGState()
        context.setFillColor(Color(red: 0.8, green: 0.1, blue: 0.8, alpha: 0.25)) // Semi-transparent magenta disk
        context.setStrokeColor(Color(red: 0.8, green: 0.1, blue: 0.8, alpha: 0.85)) // Solid magenta border
        context.setLineWidth(3.0)

        let circleCenter3D = Point3D(x: 120, y: 50, z: 200)
        let circleRadius = 45.0
        var circlePoints: [Point] = []
        for i in 0 ..< 64 {
            let theta = (Double(i) / 64.0) * 2.0 * Double.pi
            let px = circleCenter3D.x + circleRadius * cos(theta)
            let pz = circleCenter3D.z + circleRadius * sin(theta)
            let py = circleCenter3D.y // Horizontal plane

            let pt3d = Point3D(x: px, y: py, z: pz)
            let p2d = pt3d.projected(viewportSize: 500, cameraDistance: 300)
            circlePoints.append(p2d)
        }

        context.addLines(between: circlePoints)
        context.closeSubpath()
        context.fillPath()

        context.addLines(between: circlePoints)
        context.closeSubpath()
        context.strokePath()
        context.restoreGState()

        for (face, _) in sortedFaces {
            context.saveGState()

            // Set face color
            context.setFillColor(face.color)
            context.setStrokeColor(Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
            context.setLineWidth(2.0)

            // Draw face path
            let pStart = transformedVertices[face.indices[0]].projected(viewportSize: 500, cameraDistance: 300)
            context.move(to: pStart)
            for i in 1 ..< face.indices.count {
                let pt = transformedVertices[face.indices[i]].projected(viewportSize: 500, cameraDistance: 300)
                context.addLine(to: pt)
            }
            context.closeSubpath()

            context.fillPath()

            // Redraw path for stroke
            context.move(to: pStart)
            for i in 1 ..< face.indices.count {
                let pt = transformedVertices[face.indices[i]].projected(viewportSize: 500, cameraDistance: 300)
                context.addLine(to: pt)
            }
            context.closeSubpath()
            context.strokePath()

            // Draw a grid and circles on the front face (indices [0, 1, 2, 3]) to show perspective distortion of 2D geometry
            if face.indices == [0, 1, 2, 3] {
                // Get the projected 2D coordinates of the 4 front face corners
                let p0 = transformedVertices[0].projected(viewportSize: 500, cameraDistance: 300)
                let p1 = transformedVertices[1].projected(viewportSize: 500, cameraDistance: 300)
                let p2 = transformedVertices[2].projected(viewportSize: 500, cameraDistance: 300)
                let p3 = transformedVertices[3].projected(viewportSize: 500, cameraDistance: 300)

                // Create a ProjectiveTransform from the face rectangle in 2D space to its projected 3D coordinates
                let faceRect = Rect(x: -half, y: -half, width: 2.0 * half, height: 2.0 * half)
                let faceTransform = ProjectiveTransform.rectToQuad(faceRect, p0: p0, p1: p1, p2: p2, p3: p3)

                context.saveGState()
                context.setStrokeColor(Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.85))
                context.setLineWidth(1.5)

                // Build a standard 2D grid path (without manual 3D rotation loops!)
                var grid2D = Path()
                for uFactor in stride(from: -0.6, through: 0.6, by: 0.3) {
                    let x = uFactor * half
                    grid2D.move(to: Point(x: x, y: -half))
                    grid2D.addLine(to: Point(x: x, y: half))
                }
                for vFactor in stride(from: -0.6, through: 0.6, by: 0.3) {
                    let y = vFactor * half
                    grid2D.move(to: Point(x: -half, y: y))
                    grid2D.addLine(to: Point(x: half, y: y))
                }

                // Apply the projective transform to the 2D grid path and stroke it
                let distortedGrid = grid2D.applying(faceTransform)
                context.addPath(distortedGrid)
                context.strokePath()

                // Build standard 2D concentric circles path
                var circles2D = Path()
                for rFactor in [0.3, 0.65] {
                    let r = rFactor * half
                    circles2D.addEllipse(in: Rect(x: -r, y: -r, width: 2.0 * r, height: 2.0 * r))
                }

                // Apply the projective transform to the 2D circles path and stroke it
                let distortedCircles = circles2D.applying(faceTransform)
                context.addPath(distortedCircles)
                context.strokePath()

                context.restoreGState()
            }

            context.restoreGState()
        }

        // 4. Draw a crumpled/squashed piece of grid paper in the bottom-left
        let paperRect = Rect(x: 50, y: 320, width: 120, height: 120)
        let crumpleCenter = Point(x: 110, y: 380)
        let crumpleDeformer = CrumpleDeformer(center: crumpleCenter, radius: 80.0, pinchStrength: 0.45, wrinkleStrength: 1.0)

        // Build paper border path
        var paperBG = Path()
        paperBG.move(to: paperRect.origin)
        paperBG.addLine(to: Point(x: paperRect.maxX, y: paperRect.minY))
        paperBG.addLine(to: Point(x: paperRect.maxX, y: paperRect.maxY))
        paperBG.addLine(to: Point(x: paperRect.minX, y: paperRect.maxY))
        paperBG.closeSubpath()
        // Subdivide it finely (max segment length 2.0 to make it super smooth and detailed)
        let subdividedBG = paperBG.subdivided(maxSegmentLength: 2.0)
        let crumpledBG = subdividedBG.deforming { crumpleDeformer.transform($0) }

        context.saveGState()

        // Draw crumpled yellow paper shadow
        context.setShadow(offset: Point(x: 3, y: 3), blur: 5.0, color: Color(red: 0, green: 0, blue: 0, alpha: 0.4))

        // Draw crumpled yellow paper background
        context.setFillColor(Color(red: 0.98, green: 0.95, blue: 0.75, alpha: 0.9))
        context.addPath(crumpledBG)
        context.fillPath()

        // Reset shadow
        context.setShadow(offset: .zero, blur: 0, color: .clear)

        // Draw paper border line
        context.setStrokeColor(Color(red: 0.7, green: 0.65, blue: 0.45))
        context.setLineWidth(1.5)
        context.addPath(crumpledBG)
        context.strokePath()

        // Draw grid lines on the paper
        var paperGrid = Path()
        let step = 15.0
        for x in stride(from: paperRect.minX + step, to: paperRect.maxX, by: step) {
            paperGrid.move(to: Point(x: x, y: paperRect.minY))
            paperGrid.addLine(to: Point(x: x, y: paperRect.maxY))
        }
        for y in stride(from: paperRect.minY + step, to: paperRect.maxY, by: step) {
            paperGrid.move(to: Point(x: paperRect.minX, y: y))
            paperGrid.addLine(to: Point(x: paperRect.maxX, y: y))
        }

        let subdividedGrid = paperGrid.subdivided(maxSegmentLength: 2.0)
        let crumpledGrid = subdividedGrid.deforming { crumpleDeformer.transform($0) }

        context.setStrokeColor(Color(red: 0.6, green: 0.75, blue: 0.85, alpha: 0.6))
        context.setLineWidth(1.0)
        context.addPath(crumpledGrid)
        context.strokePath()

        context.restoreGState()

        // 5. Draw overlapping blend-mode circles in the bottom-right (Multiply test)
        context.saveGState()

        // Circle 1 (Magenta)
        context.setFillColor(Color(red: 0.9, green: 0.1, blue: 0.6, alpha: 0.8))
        context.addEllipse(in: Rect(x: 345, y: 345, width: 70, height: 70))
        context.fillPath()

        // Set multiply blend mode for Circle 2
        context.setBlendMode(.multiply)

        // Circle 2 (Cyan)
        context.setFillColor(Color(red: 0.1, green: 0.8, blue: 0.8, alpha: 0.8))
        context.addEllipse(in: Rect(x: 385, y: 345, width: 70, height: 70))
        context.fillPath()

        context.restoreGState()

        // Render to PDF
        let pdfData = try PDFRenderer(width: 500, height: 500).render(context)

        // Write PDF data to the workspace directory
        let outputPath = "3d_transform_scene.pdf"
        try pdfData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated 3D perspective scene at: \(outputPath)")

        // Render to HTML Canvas page
        let htmlData = try CanvasRenderer().renderToHTMLPage(context, width: 500, height: 500)
        let htmlPath = "3d_transform_scene.html"
        try htmlData.write(to: URL(fileURLWithPath: htmlPath), atomically: true, encoding: .utf8)
        print("Generated 3D HTML Canvas preview at: \(htmlPath)")
    }

    @Test func allBlendModesExecutionAndValidation() throws {
        for mode in BlendMode.allCases {
            var context = GraphicsContext()
            context.saveGState()
            context.setBlendMode(mode)
            context.setFillColor(Color(red: 1.0, green: 0.0, blue: 0.0))
            context.addRect(Rect(x: 10, y: 10, width: 50, height: 50))
            context.fillPath()
            context.restoreGState()

            // 1. SVG Renderer
            let svg = try SVGRenderer().render(context)
            if mode != .normal, mode.isCSSBlendMode {
                #expect(svg.contains("style=\"mix-blend-mode: \(mode.rawValue)\""))
            } else {
                #expect(!svg.contains("style=\"mix-blend-mode:"))
            }

            // 2. Canvas Renderer
            let canvas = try CanvasRenderer().render(context)
            if mode != .normal {
                let expectedCanvasString = switch mode {
                case .plusLighter: "lighter"
                case .plusDarker: "darker"
                default: mode.rawValue
                }
                #expect(canvas.contains("globalCompositeOperation = '\(expectedCanvasString)'"))
            } else {
                #expect(!canvas.contains("globalCompositeOperation"))
            }

            // 3. PDF Renderer
            let pdf = try PDFRenderer(width: 100, height: 100).render(context)
            #expect(!pdf.isEmpty)

            // 4. PostScript Renderer
            let ps = try PostScriptRenderer(width: 100, height: 100).render(context)
            #expect(!ps.isEmpty)

            // 5. CoreGraphics Renderer (if available)
            #if canImport(CoreGraphics)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let cgContext = CGContext(
                    data: nil,
                    width: 100,
                    height: 100,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) {
                    try CoreGraphicsRenderer(context: cgContext).render(context)
                } else {
                    Issue.record("Failed to create offscreen CGContext in blend mode tests")
                }
            #endif
        }
    }
}
