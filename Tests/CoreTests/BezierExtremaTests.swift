//
//  BezierExtremaTests.swift
//  PureDraw
//
//  Canaries for the curve-tightness of `boundingBox`. The shape/figure containment trips
//  assert "boundingBox lies within the frame", which is only sound if boundingBox accounts
//  for a Bezier's interior extrema, not just its endpoints or its control-point hull. If it
//  under-reported an extremum, a curve could poke outside the frame while a containment check
//  still passed. These assert boundingBox against extrema derived by hand, independent of the
//  implementation: a curve's peak is computed from the Bezier formula, not read back from it.
//

@testable import Core
import Geometry
import Testing

struct BezierExtremaTests {
    @Test func boundingBoxComputesTrueQuadraticExtrema() {
        // Quadratic (0,0) -> (10,0), control (5,10). y(t) = 2(1-t)t*10, peak at t=0.5 is
        // 20*0.25 = 5: NOT the control's y=10, NOT the endpoints' 0. A control-hull bbox would
        // wrongly report maxY=10; an endpoints-only bbox would report 0.
        var path = Path()
        path.move(to: Point(x: 0, y: 0))
        path.addQuadCurve(to: Point(x: 10, y: 0), control: Point(x: 5, y: 10))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01 && abs(box.maxX - 10) < 0.01, "x spans the endpoints [0,10]; got [\(box.minX),\(box.maxX)]")
        #expect(abs(box.minY - 0) < 0.01, "min y is at the endpoints (0); got \(box.minY)")
        #expect(abs(box.maxY - 5) < 0.01, "max y is the curve peak 5, not the control's 10; got \(box.maxY)")
    }

    @Test func boundingBoxComputesTrueCubicExtrema() {
        // Cubic (0,0) -> (30,0), controls (10,30) and (20,30). y(t) = 90 t(1-t), peak at
        // t=0.5 is 90*0.25 = 22.5: NOT the controls' y=30. boundingBox must be curve-tight.
        var path = Path()
        path.move(to: Point(x: 0, y: 0))
        path.addCurve(to: Point(x: 30, y: 0), control1: Point(x: 10, y: 30), control2: Point(x: 20, y: 30))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01 && abs(box.maxX - 30) < 0.01, "x spans the endpoints [0,30]; got [\(box.minX),\(box.maxX)]")
        #expect(abs(box.minY - 0) < 0.01, "min y is at the endpoints (0); got \(box.minY)")
        #expect(abs(box.maxY - 22.5) < 0.01, "max y is the curve peak 22.5, not the controls' 30; got \(box.maxY)")
    }
}
