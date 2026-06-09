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
}
