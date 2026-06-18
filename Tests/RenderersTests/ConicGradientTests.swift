//
//  ConicGradientTests.swift
//  PureDraw
//
//  Conic (angular / sweep) gradients (PureDraw #118): the stops sweep around a center from a
//  start angle through a full turn. BitmapRenderer rasterizes them per pixel and CanvasRenderer
//  maps them to createConicGradient; the pure-vector exporters (SVG, PDF, PostScript) and
//  CoreGraphics, which have no conic shading, fail loud rather than drop the fill.
//

import Core
import Foundation
import Geometry
import Renderers
import Testing

struct ConicGradientTests {
    private let w = 80
    private let h = 80

    private func red(_ image: Image, _ x: Int, _ y: Int) -> Int {
        Int(image.data[(y * w + x) * 4])
    }

    /// A black->white sweep around the canvas centre, sampled at the four cardinal directions.
    private func sweepImage() throws -> Image {
        var c = GraphicsContext()
        let gradient = Gradient(stops: [GradientStop(color: .black, location: 0), GradientStop(color: .white, location: 1)])
        c.drawConicGradient(gradient, center: Point(x: 40, y: 40), startAngle: 0)
        return try BitmapRenderer(width: w, height: h).render(c)
    }

    @Test func bitmapConicSweepsByAngle() throws {
        // startAngle 0 sweeps clockwise from +x (device y is down). t = angle / 2pi, so the
        // black->white ramp gives red ~ 255*t at each cardinal direction from the centre.
        let image = try sweepImage()
        #expect(abs(red(image, 70, 40) - 0) <= 20, "right of centre (angle 0) should be ~black")
        #expect(abs(red(image, 40, 70) - 64) <= 24, "below centre (1/4 turn) should be ~quarter")
        #expect(abs(red(image, 10, 40) - 128) <= 24, "left of centre (1/2 turn) should be ~mid grey")
        #expect(abs(red(image, 40, 10) - 191) <= 24, "above centre (3/4 turn) should be ~three-quarter")
    }

    @Test func canvasEmitsCreateConicGradient() throws {
        var c = GraphicsContext()
        let gradient = Gradient(stops: [GradientStop(color: .black, location: 0), GradientStop(color: .white, location: 1)])
        c.drawConicGradient(gradient, center: Point(x: 20, y: 30), startAngle: 0.5)
        let js = try CanvasRenderer().render(c)
        #expect(js.contains("createConicGradient(0.5, 20.0, 30.0)"), "must map to createConicGradient(startAngle, x, y)")
        #expect(js.contains("addColorStop"), "must emit the gradient stops")
    }

    @Test func vectorExportersFailLoudOnConic() throws {
        var c = GraphicsContext()
        let gradient = Gradient(stops: [GradientStop(color: .black, location: 0), GradientStop(color: .white, location: 1)])
        c.drawConicGradient(gradient, center: Point(x: 40, y: 40), startAngle: 0)
        #expect(throws: UnsupportedOperationError.self) { _ = try SVGRenderer().render(c) }
        #expect(throws: UnsupportedOperationError.self) { _ = try PostScriptRenderer().render(c) }
        #expect(throws: UnsupportedOperationError.self) { _ = try PDFRenderer(width: Double(w), height: Double(h)).render(c) }
    }
}
