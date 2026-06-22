//
//  ShadingTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing

/// A shading is a first-class colour-function object that lowers to the gradient
/// machinery. These assert the lowering is exact (drawing a shading records the
/// same operation as the equivalent gradient draw) and that the extend flags map
/// to the gradient drawing options, so there is no second code path to drift.
struct ShadingTests {
    private func ramp(_ t: Double) -> Color {
        Color(red: t, green: 1 - t, blue: 0, alpha: 1)
    }

    @Test func axialShadingLowersToLinearGradient() {
        let start = Point(x: 0, y: 0)
        let end = Point(x: 10, y: 0)
        let shading = Shading(axialFrom: start, to: end, extendStart: true, extendEnd: true, samples: 64, function: ramp)

        var lowered = GraphicsContext()
        lowered.drawShading(shading)

        var expected = GraphicsContext()
        expected.drawLinearGradient(
            Gradient(samples: 64, ramp),
            start: start,
            end: end,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        #expect(lowered.commands == expected.commands)
    }

    @Test func radialShadingLowersToRadialGradient() {
        let shading = Shading(
            radialFrom: Point(x: 5, y: 5), radius: 0,
            to: Point(x: 5, y: 5), radius: 8,
            samples: 64, function: ramp
        )

        var lowered = GraphicsContext()
        lowered.drawShading(shading)

        var expected = GraphicsContext()
        expected.drawRadialGradient(
            Gradient(samples: 64, ramp),
            startCenter: Point(x: 5, y: 5), startRadius: 0,
            endCenter: Point(x: 5, y: 5), endRadius: 8,
            options: []
        )

        #expect(lowered.commands == expected.commands)
    }

    @Test func extendFlagsMapToGradientOptions() {
        let neither = Shading(axialFrom: .zero, to: Point(x: 1, y: 0), function: ramp)
        #expect(neither.drawingOptions == [])

        let both = Shading(axialFrom: .zero, to: Point(x: 1, y: 0), extendStart: true, extendEnd: true, function: ramp)
        #expect(both.drawingOptions == [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        let startOnly = Shading(axialFrom: .zero, to: Point(x: 1, y: 0), extendStart: true, function: ramp)
        #expect(startOnly.drawingOptions == [.drawsBeforeStartLocation])
    }

    @Test func sampledFunctionPopulatesTheGradient() {
        let shading = Shading(axialFrom: .zero, to: Point(x: 1, y: 0), samples: 8, function: ramp)
        #expect(shading.gradient.stops.count == 8)
        // The first sample is the function at t = 0, the last at t = 1.
        #expect(shading.gradient.stops.first?.color == ramp(0))
        #expect(shading.gradient.stops.last?.color == ramp(1))
    }
}
