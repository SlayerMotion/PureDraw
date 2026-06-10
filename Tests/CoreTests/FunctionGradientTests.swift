//
//  FunctionGradientTests.swift
//  PureDraw
//

@testable import Core
import Testing

struct FunctionGradientTests {
    @Test func samplesFunctionIntoStops() {
        // A gamma ramp: red rises as t squared, blue falls linearly.
        let gradient = Gradient(samples: 5) { t in
            Color(red: t * t, green: 0, blue: 1 - t, alpha: 1)
        }

        #expect(gradient.stops.count == 5)
        #expect(gradient.stops.first?.location == 0)
        #expect(gradient.stops.last?.location == 1)

        // Midpoint t = 0.5: red = 0.25, blue = 0.5.
        let mid = gradient.stops[2]
        #expect(mid.location == 0.5)
        #expect(abs(mid.color.red - 0.25) < 1e-9)
        #expect(abs(mid.color.blue - 0.5) < 1e-9)
    }

    @Test func clampsSampleCountToTwo() {
        let gradient = Gradient(samples: 1) { _ in .black }
        #expect(gradient.stops.count == 2)
        #expect(gradient.stops[0].location == 0)
        #expect(gradient.stops[1].location == 1)
    }

    @Test func sampledGradientValidates() throws {
        let gradient = Gradient { t in Color(red: t, green: t, blue: t, alpha: 1) }
        try gradient.validate()
        #expect(gradient.stops.count == 256)
    }
}
