//
//  BitmapRendererTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing

struct BitmapRendererTests {
    @Test func solidFill() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
        context.addRect(Rect(x: 2, y: 2, width: 6, height: 6))
        context.fillPath()

        let renderer = BitmapRenderer(width: 10, height: 10)
        let image = try renderer.render(context)

        #expect(image.width == 10)
        #expect(image.height == 10)

        let data = image.data
        for y in 0 ..< 10 {
            for x in 0 ..< 10 {
                let index = (y * 10 + x) * 4
                let isInside = (x >= 2 && x < 8 && y >= 2 && y < 8)
                if isInside {
                    #expect(data[index] == 255) // R
                    #expect(data[index + 1] == 0) // G
                    #expect(data[index + 2] == 0) // B
                    #expect(data[index + 3] == 255) // A
                } else {
                    #expect(data[index + 3] == 0) // Transparent A
                }
            }
        }
    }

    @Test func strokeLine() throws {
        var context = GraphicsContext()
        context.setStrokeColor(Color(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0))
        context.setLineWidth(2.0)
        context.setLineCap(.butt)
        context.move(to: Point(x: 0, y: 5))
        context.addLine(to: Point(x: 10, y: 5))
        context.strokePath()

        let renderer = BitmapRenderer(width: 10, height: 10)
        let image = try renderer.render(context)
        let data = image.data

        let middleIndex = (5 * 10 + 5) * 4
        #expect(data[middleIndex] == 0)
        #expect(data[middleIndex + 1] == 0)
        #expect(data[middleIndex + 2] == 255)
        #expect(data[middleIndex + 3] == 255)
    }

    @Test func clipping() throws {
        var context = GraphicsContext()

        context.addRect(Rect(x: 3, y: 3, width: 4, height: 4))
        context.clip()

        context.setFillColor(Color(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0))
        context.addRect(Rect(x: 0, y: 0, width: 10, height: 10))
        context.fillPath()

        let renderer = BitmapRenderer(width: 10, height: 10)
        let image = try renderer.render(context)
        let data = image.data

        for y in 0 ..< 10 {
            for x in 0 ..< 10 {
                let index = (y * 10 + x) * 4
                let isInsideClip = (x >= 3 && x < 7 && y >= 3 && y < 7)
                if isInsideClip {
                    #expect(data[index] == 0)
                    #expect(data[index + 1] == 255)
                    #expect(data[index + 2] == 0)
                    #expect(data[index + 3] == 255)
                } else {
                    #expect(data[index + 3] == 0)
                }
            }
        }
    }
}
