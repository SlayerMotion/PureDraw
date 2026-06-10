//
//  main.swift
//  puredraw-bench
//
//  A deterministic benchmark harness for the rasterizer hot paths. Each
//  scenario builds a fixed GraphicsContext and renders it through
//  BitmapRenderer; the harness reports median time per render. There are no
//  timing assertions, so it is safe to build in CI without being flaky; run
//  it explicitly with `swift run -c release puredraw-bench`.
//

import Core
import Geometry
import Renderers

// MARK: - Harness

struct Scenario {
    let name: String
    let canvas: Int
    let build: () -> GraphicsContext
}

func median(_ values: [Duration]) -> Duration {
    let sorted = values.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 1 {
        return sorted[mid]
    }
    return (sorted[mid - 1] + sorted[mid]) / 2
}

func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1000.0 + Double(components.attoseconds) / 1e15
}

func run(_ scenario: Scenario, warmup: Int, iterations: Int) -> (median: Double, opsPerSecond: Double) {
    let context = scenario.build()
    let renderer = BitmapRenderer(width: scenario.canvas, height: scenario.canvas)
    let clock = ContinuousClock()

    for _ in 0 ..< warmup {
        _ = try? renderer.render(context)
    }

    var samples: [Duration] = []
    samples.reserveCapacity(iterations)
    for _ in 0 ..< iterations {
        let elapsed = clock.measure {
            _ = try? renderer.render(context)
        }
        samples.append(elapsed)
    }

    let med = median(samples)
    let medMs = milliseconds(med)
    let opsPerSecond = medMs > 0 ? 1000.0 / medMs : .infinity
    return (medMs, opsPerSecond)
}

// MARK: - Scenarios

func fillScenario(antialiased: Bool) -> GraphicsContext {
    var context = GraphicsContext()
    context.setShouldAntialias(antialiased)
    // 200 overlapping triangles across the canvas.
    for index in 0 ..< 200 {
        let phase = Double(index)
        let originX = (phase * 37).truncatingRemainder(dividingBy: 220)
        let originY = (phase * 53).truncatingRemainder(dividingBy: 220)
        let red = (phase * 0.013).truncatingRemainder(dividingBy: 1)
        context.setFillColor(Color(red: red, green: 0.4, blue: 0.8, alpha: 0.6))
        context.move(to: Point(x: originX, y: originY))
        context.addLine(to: Point(x: originX + 40, y: originY + 6))
        context.addLine(to: Point(x: originX + 8, y: originY + 44))
        context.closeSubpath()
        context.fillPath()
    }
    return context
}

func strokeScenario() -> GraphicsContext {
    var context = GraphicsContext()
    context.setStrokeColor(Color(red: 0.1, green: 0.6, blue: 0.3, alpha: 1))
    context.setLineWidth(3)
    context.setLineJoin(.miter)
    for index in 0 ..< 120 {
        let phase = Double(index)
        let x = (phase * 29).truncatingRemainder(dividingBy: 200)
        let y = (phase * 41).truncatingRemainder(dividingBy: 200)
        context.move(to: Point(x: x, y: y))
        context.addLine(to: Point(x: x + 30, y: y + 10))
        context.addLine(to: Point(x: x + 12, y: y + 40))
        context.addLine(to: Point(x: x + 48, y: y + 28))
        context.strokePath()
    }
    return context
}

func gradientScenario() -> GraphicsContext {
    var context = GraphicsContext()
    let linear = Gradient(stops: [
        GradientStop(color: Color(red: 1, green: 0.8, blue: 0, alpha: 1), location: 0),
        GradientStop(color: Color(red: 0.6, green: 0, blue: 0.6, alpha: 1), location: 1),
    ])
    let radial = Gradient(samples: 64) { t in
        Color(red: t, green: 1 - t, blue: 0.5, alpha: 1)
    }
    for index in 0 ..< 12 {
        context.saveGState()
        let offset = Double(index) * 6
        context.addRect(Rect(x: offset, y: offset, width: 120, height: 120))
        context.clip()
        if index % 2 == 0 {
            context.drawLinearGradient(linear, start: Point(x: offset, y: offset), end: Point(x: offset + 120, y: offset + 120), options: [])
        } else {
            context.drawRadialGradient(
                radial,
                startCenter: Point(x: offset + 60, y: offset + 60),
                startRadius: 0,
                endCenter: Point(x: offset + 60, y: offset + 60),
                endRadius: 70,
                options: []
            )
        }
        context.restoreGState()
    }
    return context
}

func patternScenario() -> GraphicsContext {
    let pattern = Pattern(bounds: Rect(x: 0, y: 0, width: 8, height: 8), isColored: true)
    pattern.context.setFillColor(Color(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
    pattern.context.addEllipse(in: Rect(x: 1, y: 1, width: 6, height: 6))
    pattern.context.fillPath()

    var context = GraphicsContext()
    context.setFillPattern(pattern)
    context.addRect(Rect(x: 0, y: 0, width: 256, height: 256))
    context.fillPath()
    return context
}

// MARK: - Main

let scenarios: [Scenario] = [
    Scenario(name: "fill-aa", canvas: 256, build: { fillScenario(antialiased: true) }),
    Scenario(name: "fill-aliased", canvas: 256, build: { fillScenario(antialiased: false) }),
    Scenario(name: "stroke", canvas: 256, build: strokeScenario),
    Scenario(name: "gradient", canvas: 256, build: gradientScenario),
    Scenario(name: "pattern", canvas: 256, build: patternScenario),
]

let warmup = 3
let iterations = 25

print("PureDraw benchmark: median over \(iterations) iterations (\(warmup) warmup)")
print(String(repeating: "-", count: 52))
print("scenario".padded(to: 18) + "median (ms)".padded(to: 16) + "renders/sec")
print(String(repeating: "-", count: 52))
for scenario in scenarios {
    let result = run(scenario, warmup: warmup, iterations: iterations)
    let ms = String(format: "%.3f", result.median)
    let ops = String(format: "%.1f", result.opsPerSecond)
    print(scenario.name.padded(to: 18) + ms.padded(to: 16) + ops)
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
