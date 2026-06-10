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

    @Test func drawImage() throws {
        // Create a 2x2 test image (RGBA: un-premultiplied color values)
        // Red, Green, Blue, Yellow
        let imgData: [UInt8] = [
            255, 0, 0, 255, // Red
            0, 255, 0, 255, // Green
            0, 0, 255, 255, // Blue
            255, 255, 0, 128, // Yellow (half alpha)
        ]
        let testImage = Image(width: 2, height: 2, data: imgData)

        var context = GraphicsContext()
        // Draw the 2x2 image scaled to fill 4x4 rect starting at (2, 2) in a 8x8 context
        context.draw(testImage, in: Rect(x: 2, y: 2, width: 4, height: 4))

        let renderer = BitmapRenderer(width: 8, height: 8)
        let resultImage = try renderer.render(context)
        let data = resultImage.data

        // Verify the scaling and color extraction correctness.
        // The drawn image spans x inside [2, 6) and y inside [2, 6).
        // Since it's scaled 2x, each pixel in the source is 2x2 in the destination:
        // Top-left of drawing (2, 2) to (3, 3) should be Red.
        // Top-right of drawing (4, 2) to (5, 3) should be Green.
        // Bottom-left of drawing (2, 4) to (3, 5) should be Blue.
        // Bottom-right of drawing (4, 4) to (5, 5) should be Yellow (half transparent).

        for y in 0 ..< 8 {
            for x in 0 ..< 8 {
                let idx = (y * 8 + x) * 4
                if x >= 2, x < 4, y >= 2, y < 4 {
                    // Red
                    #expect(data[idx] == 255)
                    #expect(data[idx + 1] == 0)
                    #expect(data[idx + 2] == 0)
                    #expect(data[idx + 3] == 255)
                } else if x >= 4, x < 6, y >= 2, y < 4 {
                    // Green
                    #expect(data[idx] == 0)
                    #expect(data[idx + 1] == 255)
                    #expect(data[idx + 2] == 0)
                    #expect(data[idx + 3] == 255)
                } else if x >= 2, x < 4, y >= 4, y < 6 {
                    // Blue
                    #expect(data[idx] == 0)
                    #expect(data[idx + 1] == 0)
                    #expect(data[idx + 2] == 255)
                    #expect(data[idx + 3] == 255)
                } else if x >= 4, x < 6, y >= 4, y < 6 {
                    // Yellow (half alpha)
                    // Yellow is Red+Green = [255, 255, 0].
                    // Since alpha is 128/255.0 = ~0.50196
                    #expect(data[idx] == 255)
                    #expect(data[idx + 1] == 255)
                    #expect(data[idx + 2] == 0)
                    #expect(data[idx + 3] == 128)
                } else {
                    // Transparent
                    #expect(data[idx + 3] == 0)
                }
            }
        }
    }
}
