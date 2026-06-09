//
//  RendererTests.swift
//  PureDraw
//

import Testing
import Foundation
@testable import PureDraw

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
            GradientStop(color: .black, location: 1.0)
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
            GradientStop(color: .black, location: 1.0)
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
                return Point3D(x: x + dx, y: y + dy, z: z + dz)
            }
            
            func projected(viewportSize: Double, cameraDistance: Double) -> Point {
                let factor = cameraDistance / (z + cameraDistance)
                let px = x * factor + viewportSize / 2.0
                let py = y * factor + viewportSize / 2.0
                return Point(x: px, y: py)
            }
        }
        
        var context = GraphicsContext()
        
        // 1. Background Gradient
        let bgStops = [
            GradientStop(color: Color(red: 0.05, green: 0.05, blue: 0.15), location: 0.0),
            GradientStop(color: Color(red: 0.15, green: 0.15, blue: 0.35), location: 1.0)
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
        
        // Draw badge background
        context.setFillColor(Color(red: 0.9, green: 0.5, blue: 0.1, alpha: 0.85))
        context.addRoundedRect(in: Rect(x: 0, y: 0, width: 120, height: 40), cornerWidth: 5, cornerHeight: 5)
        context.fillPath()
        
        // Draw badge border
        context.setStrokeColor(.white)
        context.setLineWidth(2.0)
        context.addRoundedRect(in: Rect(x: 0, y: 0, width: 120, height: 40), cornerWidth: 5, cornerHeight: 5)
        context.strokePath()
        
        context.restoreGState()
        
        // 3. 3D Cube sitting on grid
        let half: Double = 60
        let cubeVertices = [
            Point3D(x: -half, y: -half, z: -half), // 0
            Point3D(x: half, y: -half, z: -half),  // 1
            Point3D(x: half, y: half, z: -half),   // 2
            Point3D(x: -half, y: half, z: -half),  // 3
            Point3D(x: -half, y: -half, z: half),  // 4
            Point3D(x: half, y: -half, z: half),   // 5
            Point3D(x: half, y: half, z: half),    // 6
            Point3D(x: -half, y: half, z: half)    // 7
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
            Face(indices: [1, 5, 6, 2], color: Color(red: 0.2, green: 0.9, blue: 0.9, alpha: 0.7))  // Right (Cyan)
        ]
        
        // Sort faces by depth (painter's algorithm)
        let sortedFaces = faces.map { face -> (Face, Double) in
            let avgZ = face.indices.map { transformedVertices[$0].z }.reduce(0.0, +) / 4.0
            return (face, avgZ)
        }.sorted(by: { $0.1 > $1.1 }) // Draw further faces first
        
        for (face, _) in sortedFaces {
            context.saveGState()
            
            // Set face color
            context.setFillColor(face.color)
            context.setStrokeColor(Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
            context.setLineWidth(2.0)
            
            // Draw face path
            let pStart = transformedVertices[face.indices[0]].projected(viewportSize: 500, cameraDistance: 300)
            context.move(to: pStart)
            for i in 1..<face.indices.count {
                let pt = transformedVertices[face.indices[i]].projected(viewportSize: 500, cameraDistance: 300)
                context.addLine(to: pt)
            }
            context.closeSubpath()
            
            context.fillPath()
            
            // Redraw path for stroke
            context.move(to: pStart)
            for i in 1..<face.indices.count {
                let pt = transformedVertices[face.indices[i]].projected(viewportSize: 500, cameraDistance: 300)
                context.addLine(to: pt)
            }
            context.closeSubpath()
            context.strokePath()
            
            // Draw a grid and circles on the front face (indices [0, 1, 2, 3]) to show perspective distortion of 2D geometry
            if face.indices == [0, 1, 2, 3] {
                context.saveGState()
                context.setStrokeColor(Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.85))
                context.setLineWidth(1.5)
                
                // Vertical lines on the face (constant u, varying v)
                for uFactor in stride(from: -0.6, through: 0.6, by: 0.3) {
                    var pathStarted = false
                    for vFactor in stride(from: -1.0, through: 1.0, by: 0.1) {
                        let localPt = Point3D(x: uFactor * half, y: vFactor * half, z: -half)
                        let rotPt = localPt.rotatedY(rotY).rotatedX(rotX).translated(dx: transX, dy: transY, dz: transZ)
                        let projPt = rotPt.projected(viewportSize: 500, cameraDistance: 300)
                        if !pathStarted {
                            context.move(to: projPt)
                            pathStarted = true
                        } else {
                            context.addLine(to: projPt)
                        }
                    }
                    context.strokePath()
                }
                
                // Horizontal lines on the face (constant v, varying u)
                for vFactor in stride(from: -0.6, through: 0.6, by: 0.3) {
                    var pathStarted = false
                    for uFactor in stride(from: -1.0, through: 1.0, by: 0.1) {
                        let localPt = Point3D(x: uFactor * half, y: vFactor * half, z: -half)
                        let rotPt = localPt.rotatedY(rotY).rotatedX(rotX).translated(dx: transX, dy: transY, dz: transZ)
                        let projPt = rotPt.projected(viewportSize: 500, cameraDistance: 300)
                        if !pathStarted {
                            context.move(to: projPt)
                            pathStarted = true
                        } else {
                            context.addLine(to: projPt)
                        }
                    }
                    context.strokePath()
                }
                
                // Concentric circles on the face
                for rFactor in [0.3, 0.65] {
                    var pathStarted = false
                    for angle in stride(from: 0.0, through: 2.0 * Double.pi + 0.1, by: 0.1) {
                        let localPt = Point3D(x: cos(angle) * rFactor * half, y: sin(angle) * rFactor * half, z: -half)
                        let rotPt = localPt.rotatedY(rotY).rotatedX(rotX).translated(dx: transX, dy: transY, dz: transZ)
                        let projPt = rotPt.projected(viewportSize: 500, cameraDistance: 300)
                        if !pathStarted {
                            context.move(to: projPt)
                            pathStarted = true
                        } else {
                            context.addLine(to: projPt)
                        }
                    }
                    context.strokePath()
                }
                context.restoreGState()
            }
            
            context.restoreGState()
        }
        
        // Render to PDF
        let pdfData = try PDFRenderer(width: 500, height: 500).render(context)
        
        // Write PDF data to the workspace directory
        let outputPath = "/Volumes/Code/DeveloperExt/public/PureDraw/3d_transform_scene.pdf"
        try pdfData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated 3D perspective scene at: \(outputPath)")
    }
}
