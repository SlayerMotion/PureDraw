//
//  PathBooleanTests.swift
//  PureDraw
//
//  Boolean path operations (PureDraw #109) verified by the set-algebra area invariants that
//  would catch a mistraced contour: area(A and B) + area(A or B) = area(A) + area(B),
//  area(A - B) = area(A) - area(A and B), and the symmetric difference = union minus
//  intersection. Plus the no-crossing cases (disjoint, containment) the tracer routes around
//  explicitly. Covered area is measured by rasterizing the result (anti-aliased alpha sum),
//  which gives the true filled region regardless of contour orientation or holes -- a signed
//  shoelace would cancel the oppositely-wound pieces of a symmetric difference.
//

import Core
import Geometry
import Renderers
import Testing

struct PathBooleanTests {
    /// The covered area of `path`, as the anti-aliased filled coverage under the nonzero rule.
    private func area(_ path: Path) -> Double {
        var c = GraphicsContext()
        c.setFillColor(.white)
        c.addPath(path)
        c.fillPath(using: .winding)
        guard let image = try? BitmapRenderer(width: 64, height: 64).render(c) else { return 0 }
        var sum = 0.0
        for i in stride(from: 3, to: image.data.count, by: 4) {
            sum += Double(image.data[i]) / 255.0
        }
        return sum
    }

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
        Path(rect: Rect(x: x, y: y, width: w, height: h))
    }

    /// A diamond (rotated square) so overlaps with axis-aligned shapes cross edges
    /// transversally (no shared edges).
    private func diamond(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
        var p = Path()
        p.move(to: Point(x: cx, y: cy - r))
        p.addLine(to: Point(x: cx + r, y: cy))
        p.addLine(to: Point(x: cx, y: cy + r))
        p.addLine(to: Point(x: cx - r, y: cy))
        p.closeSubpath()
        return p
    }

    private func expectInvariants(_ a: Path, _ b: Path, tol: Double = 2.5, _ label: String) {
        let areaA = area(a), areaB = area(b)
        let inter = area(a.intersection(b))
        let uni = area(a.union(b))
        let diff = area(a.subtracting(b))
        let sym = area(a.symmetricDifference(b))
        #expect(abs((inter + uni) - (areaA + areaB)) <= tol, "\(label): inter+union vs areaA+areaB (\(inter)+\(uni) vs \(areaA)+\(areaB))")
        #expect(abs(diff - (areaA - inter)) <= tol, "\(label): A-B vs areaA-inter (\(diff) vs \(areaA - inter))")
        #expect(abs(sym - (uni - inter)) <= tol, "\(label): symmetric diff vs union-inter (\(sym) vs \(uni - inter))")
    }

    @Test func overlappingDiamondAndSquare() {
        expectInvariants(diamond(20, 20, 12), rect(16, 16, 16, 16), "diamond over square")
    }

    @Test func twoOverlappingDiamonds() {
        expectInvariants(diamond(22, 22, 11), diamond(30, 26, 11), "two diamonds")
    }

    @Test func disjointShapes() {
        let a = rect(2, 2, 12, 12), b = rect(40, 40, 12, 12)
        #expect(area(a.intersection(b)) <= 2.0, "disjoint intersection is empty")
        #expect(abs(area(a.union(b)) - (area(a) + area(b))) <= 2.5, "disjoint union is both areas")
        #expect(abs(area(a.subtracting(b)) - area(a)) <= 2.5, "disjoint difference is the subject")
    }

    @Test func containment() {
        let outer = rect(6, 6, 40, 40), inner = rect(18, 18, 12, 12) // inner fully inside outer
        #expect(abs(area(outer.intersection(inner)) - area(inner)) <= 2.5, "intersection is the inner shape")
        #expect(abs(area(outer.union(inner)) - area(outer)) <= 2.5, "union is the outer shape")
        #expect(abs(area(outer.subtracting(inner)) - (area(outer) - area(inner))) <= 2.5, "outer minus inner leaves a hole")
    }

    @Test func degenerateSharedEdgesAreNudged() {
        // Two identical axis-aligned squares share every edge (the worst degeneracy); the nudge
        // fallback should still give union and intersection both ~= one square.
        let a = rect(10, 10, 20, 20), b = rect(10, 10, 20, 20)
        #expect(abs(area(a.union(b)) - area(a)) <= 6.0, "union of identical squares is one square")
        #expect(abs(area(a.intersection(b)) - area(a)) <= 6.0, "intersection of identical squares is one square")
    }
}
