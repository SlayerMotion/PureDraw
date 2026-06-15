//
//  StrokeOutline.swift
//  PureDraw
//

import Foundation
import Geometry

public extension Path {
    /// The filled outline of this path stroked with the given parameters: the region a stroke
    /// would cover, returned as a path to be filled with the nonzero winding rule.
    ///
    /// Mirrors Core Graphics' `CGContextReplacePathWithStrokedPath` and
    /// `CGPath.copy(strokingWithWidth:lineCap:lineJoin:miterLimit:transform:)`. Filling the
    /// result paints exactly what stroking this path would. `lineWidth`, `dashLengths`, and
    /// `dashPhase` are in this path's own coordinate space; an empty (or all-zero) `dashLengths`
    /// strokes solid. This is the single source of the stroke geometry the bitmap renderer
    /// rasterizes, so an outline and a rasterized stroke cannot drift.
    func strokedOutline(
        lineWidth: Double,
        lineCap: LineCap = .butt,
        lineJoin: LineJoin = .miter,
        miterLimit: Double = 10,
        dashLengths: [Double] = [],
        dashPhase: Double = 0
    ) -> Path {
        let halfW = lineWidth / 2
        let dash = dashLengths.contains { $0 > 0 } ? dashLengths : []
        var outline = Path()
        for polyline in toPolylines() {
            let runs = dash.isEmpty ? [polyline] : StrokeOutlineGeometry.dashedRuns(polyline, lengths: dash, phase: dashPhase)
            for run in runs {
                StrokeOutlineGeometry.append(
                    for: run, halfW: halfW, lineCap: lineCap, lineJoin: lineJoin, miterLimit: miterLimit, into: &outline
                )
            }
        }
        return outline
    }
}

/// The stroke-to-outline geometry: segment quads, joins (miter/round/bevel), caps
/// (butt/round/square), and dash splitting. A union of positively-oriented pieces, filled with
/// the nonzero winding rule so overlaps blend exactly once.
enum StrokeOutlineGeometry {
    static func append(
        for polyline: (points: [Point], isClosed: Bool),
        halfW: Double,
        lineCap: LineCap,
        lineJoin: LineJoin,
        miterLimit: Double,
        into shape: inout Path
    ) {
        // Collapse consecutive duplicates so joins are well defined.
        var points: [Point] = []
        for point in polyline.points where point != points.last {
            points.append(point)
        }
        var isClosed = polyline.isClosed
        if isClosed, points.count >= 2, points.first == points.last {
            points.removeLast()
        }
        if isClosed, points.count < 3 {
            isClosed = false
        }

        guard points.count >= 2 else {
            if points.count == 1, lineCap == .round {
                appendDisk(center: points[0], radius: halfW, into: &shape)
            }
            return
        }

        let segmentCount = isClosed ? points.count : points.count - 1
        for i in 0 ..< segmentCount {
            appendSegmentQuad(a: points[i], b: points[(i + 1) % points.count], halfW: halfW, into: &shape)
        }

        let joinIndices = isClosed ? Array(0 ..< points.count) : Array(1 ..< points.count - 1)
        for i in joinIndices {
            let previous = points[(i - 1 + points.count) % points.count]
            let next = points[(i + 1) % points.count]
            appendJoin(at: points[i], from: previous, to: next, halfW: halfW, lineJoin: lineJoin, miterLimit: miterLimit, into: &shape)
        }

        if !isClosed {
            appendCap(at: points[0], awayFrom: points[1], halfW: halfW, lineCap: lineCap, into: &shape)
            appendCap(at: points[points.count - 1], awayFrom: points[points.count - 2], halfW: halfW, lineCap: lineCap, into: &shape)
        }
    }

    /// Splits `polyline` into its "on"-dash runs along its arc length, given `lengths`
    /// (alternating on/off) and a starting `phase`. Each run is an open polyline so the stroke
    /// caps land at the dash ends. An odd-count pattern repeats to an even length and a closed
    /// polyline is walked around its closing edge, both matching Core Graphics.
    static func dashedRuns(
        _ polyline: (points: [Point], isClosed: Bool),
        lengths rawLengths: [Double],
        phase: Double
    ) -> [(points: [Point], isClosed: Bool)] {
        var lengths = rawLengths.map { max(0, $0) }
        if !lengths.count.isMultiple(of: 2) { lengths += lengths }
        let cycle = lengths.reduce(0, +)
        guard cycle > 0 else { return [polyline] }

        var points = polyline.points
        if polyline.isClosed, let first = points.first, let last = points.last, first != last {
            points.append(first)
        }
        guard points.count >= 2 else { return [] }

        // Walk the dash cursor forward by `phase` (reduced into one cycle).
        var index = 0
        var remaining = lengths[0]
        var on = true
        var skip = phase.truncatingRemainder(dividingBy: cycle)
        if skip < 0 { skip += cycle }
        var steps = 0
        while skip > 1e-12, steps < lengths.count * 2 + 2 {
            steps += 1
            if remaining <= 1e-12 {
                index = (index + 1) % lengths.count
                remaining = lengths[index]
                on.toggle()
                continue
            }
            let step = min(remaining, skip)
            remaining -= step
            skip -= step
            if remaining <= 1e-12 {
                index = (index + 1) % lengths.count
                remaining = lengths[index]
                on.toggle()
            }
        }

        var runs: [(points: [Point], isClosed: Bool)] = []
        var current: [Point] = []
        func flush() {
            if current.count >= 2 { runs.append((current, false)) }
            current = []
        }

        for segment in 0 ..< points.count - 1 {
            let a = points[segment]
            let b = points[segment + 1]
            let segmentLength = distance(a, b)
            guard segmentLength > 0 else { continue }
            var consumed = 0.0
            var zeroGuard = 0
            while consumed < segmentLength - 1e-12 {
                if remaining <= 1e-12 {
                    zeroGuard += 1
                    if zeroGuard > lengths.count + 1 { break }
                    if on { flush() }
                    index = (index + 1) % lengths.count
                    remaining = lengths[index]
                    on.toggle()
                    continue
                }
                zeroGuard = 0
                let step = min(remaining, segmentLength - consumed)
                if on {
                    if current.isEmpty { current.append(lerp(a, b, consumed / segmentLength)) }
                    current.append(lerp(a, b, (consumed + step) / segmentLength))
                }
                consumed += step
                remaining -= step
                if remaining <= 1e-12 {
                    if on { flush() }
                    index = (index + 1) % lengths.count
                    remaining = lengths[index]
                    on.toggle()
                }
            }
        }
        if on { flush() }
        return runs
    }

    private static func distance(_ a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func lerp(_ a: Point, _ b: Point, _ t: Double) -> Point {
        Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// The rectangle covering a stroked segment. Vertex order keeps a positive orientation for
    /// any direction, which the winding-rule union relies on.
    private static func appendSegmentQuad(a: Point, b: Point, halfW: Double, into shape: inout Path) {
        let deltaX = b.x - a.x
        let deltaY = b.y - a.y
        let length = (deltaX * deltaX + deltaY * deltaY).squareRoot()
        guard length > 1e-9 else { return }

        let nx = -deltaY / length * halfW
        let ny = deltaX / length * halfW

        shape.move(to: Point(x: a.x + nx, y: a.y + ny))
        shape.addLine(to: Point(x: a.x - nx, y: a.y - ny))
        shape.addLine(to: Point(x: b.x - nx, y: b.y - ny))
        shape.addLine(to: Point(x: b.x + nx, y: b.y + ny))
        shape.closeSubpath()
    }

    private static func appendDisk(center: Point, radius: Double, into shape: inout Path) {
        let segments = max(16, min(64, Int(ceil(radius * 4.0))))
        shape.move(to: Point(x: center.x + radius, y: center.y))
        for step in 1 ..< segments {
            let angle = 2.0 * Double.pi * Double(step) / Double(segments)
            shape.addLine(to: Point(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
        }
        shape.closeSubpath()
    }

    private static func appendJoin(
        at pt: Point,
        from previous: Point,
        to next: Point,
        halfW: Double,
        lineJoin: LineJoin,
        miterLimit: Double,
        into shape: inout Path
    ) {
        let inX = pt.x - previous.x
        let inY = pt.y - previous.y
        let outX = next.x - pt.x
        let outY = next.y - pt.y
        let inLength = (inX * inX + inY * inY).squareRoot()
        let outLength = (outX * outX + outY * outY).squareRoot()
        guard inLength > 1e-9, outLength > 1e-9 else { return }

        let d1 = Point(x: inX / inLength, y: inY / inLength)
        let d2 = Point(x: outX / outLength, y: outY / outLength)
        let turn = d1.x * d2.y - d1.y * d2.x
        guard abs(turn) > 1e-12 else { return } // Collinear: the quads already overlap.

        if lineJoin == .round {
            appendDisk(center: pt, radius: halfW, into: &shape)
            return
        }

        // Outer normals point away from the inside of the turn; the wedge gap between the two
        // segment quads opens on that side.
        let outer1: Point
        let outer2: Point
        if turn > 0 {
            outer1 = Point(x: d1.y, y: -d1.x)
            outer2 = Point(x: d2.y, y: -d2.x)
        } else {
            outer1 = Point(x: -d1.y, y: d1.x)
            outer2 = Point(x: -d2.y, y: d2.x)
        }
        let corner1 = Point(x: pt.x + outer1.x * halfW, y: pt.y + outer1.y * halfW)
        let corner2 = Point(x: pt.x + outer2.x * halfW, y: pt.y + outer2.y * halfW)

        // Core Graphics compares 1 / sin(half the angle between segments) against the miter
        // limit; cosHalf below equals that sine.
        var miterTip: Point?
        if lineJoin == .miter {
            let bisectorX = outer1.x + outer2.x
            let bisectorY = outer1.y + outer2.y
            let bisectorLength = (bisectorX * bisectorX + bisectorY * bisectorY).squareRoot()
            if bisectorLength > 1e-9 {
                let cosHalf = (bisectorX * outer1.x + bisectorY * outer1.y) / bisectorLength
                if cosHalf > 1e-9, 1.0 / cosHalf <= miterLimit {
                    let reach = halfW / cosHalf
                    miterTip = Point(x: pt.x + bisectorX / bisectorLength * reach, y: pt.y + bisectorY / bisectorLength * reach)
                }
            }
        }

        // Emit with positive orientation so the union stays winding-consistent.
        let orientation = (corner1.x - pt.x) * (corner2.y - pt.y) - (corner1.y - pt.y) * (corner2.x - pt.x)
        let first = orientation >= 0 ? corner1 : corner2
        let second = orientation >= 0 ? corner2 : corner1
        shape.move(to: pt)
        shape.addLine(to: first)
        if let miterTip {
            shape.addLine(to: miterTip)
        }
        shape.addLine(to: second)
        shape.closeSubpath()
    }

    private static func appendCap(at end: Point, awayFrom neighbor: Point, halfW: Double, lineCap: LineCap, into shape: inout Path) {
        switch lineCap {
        case .butt:
            return

        case .round:
            appendDisk(center: end, radius: halfW, into: &shape)

        case .square:
            let dirX = end.x - neighbor.x
            let dirY = end.y - neighbor.y
            let length = (dirX * dirX + dirY * dirY).squareRoot()
            guard length > 1e-9 else { return }
            let capEnd = Point(x: end.x + dirX / length * halfW, y: end.y + dirY / length * halfW)
            appendSegmentQuad(a: end, b: capEnd, halfW: halfW, into: &shape)
        }
    }
}
