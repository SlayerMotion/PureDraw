//
//  RendererDimensionTests.swift
//  PureDraw
//

import Core
import Geometry
@testable import Renderers
import Testing
import Validation

struct RendererDimensionTests {
    @Test func nonPositiveDimensionsThrowInsteadOfTrapping() throws {
        var context = GraphicsContext()
        context.setFillColor(.black)
        context.addRect(Rect(x: 0, y: 0, width: 1, height: 1))
        context.fillPath()

        #expect(throws: ValidationError.self) {
            _ = try BitmapRenderer(width: -5, height: 10).render(context)
        }
        #expect(throws: ValidationError.self) {
            _ = try BitmapRenderer(width: 10, height: 0).render(context)
        }
    }

    @Test func positiveDimensionsRenderNormally() throws {
        var context = GraphicsContext()
        context.setFillColor(.black)
        context.addRect(Rect(x: 0, y: 0, width: 1, height: 1))
        context.fillPath()

        let image = try BitmapRenderer(width: 4, height: 4).render(context)
        #expect(image.width == 4)
    }
}
