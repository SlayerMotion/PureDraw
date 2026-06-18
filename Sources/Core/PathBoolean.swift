//
//  PathBoolean.swift
//  PureDraw
//

import Geometry

/// Geometric boolean operations on closed paths (PureDraw #109): union, intersection,
/// difference, and symmetric difference, returning a `Path`. Uses the Greiner-Hormann polygon
/// clipping algorithm on the paths' flattened polygons.
///
/// Scope and limits (intentionally disclosed): operands are flattened to polygons via
/// `toPolygons`, so curves are approximated by their flattening. The implementation handles the
/// general transversal-crossing case plus the no-crossing cases (disjoint, containment); inputs
/// whose edges are *coincident* (shared edges, e.g. two identical axis-aligned rectangles
/// touching exactly) are nudged by a sub-unit epsilon to break the degeneracy, so such results
/// are correct to within that epsilon rather than exact. Each operand is treated as a single
/// region (its polygons combined under the even-odd rule); deeply self-intersecting input is
/// not guaranteed.
public extension Path {
    /// The region covered by either path.
    func union(_ other: Path) -> Path {
        PathBoolean.combine(self, other, op: .union)
    }

    /// The region covered by both paths.
    func intersection(_ other: Path) -> Path {
        PathBoolean.combine(self, other, op: .intersection)
    }

    /// The region of `self` not covered by `other`.
    func subtracting(_ other: Path) -> Path {
        PathBoolean.combine(self, other, op: .difference)
    }

    /// The region covered by exactly one of the two paths. This is `(A - B)` together with
    /// `(B - A)`; the two are area-disjoint (they meet only along the shared `A ∩ B` boundary),
    /// so their contours are concatenated directly rather than unioned, which would hit the
    /// coincident-edge degeneracy along that shared boundary.
    func symmetricDifference(_ other: Path) -> Path {
        var result = subtracting(other)
        for poly in other.subtracting(self).toPolygons() where poly.count >= 3 {
            result.move(to: poly[0])
            for p in poly.dropFirst() {
                result.addLine(to: p)
            }
            result.closeSubpath()
        }
        return result
    }
}

enum PathBoolean {
    enum Operation { case union, intersection, difference }

    static func combine(_ a: Path, _ b: Path, op: Operation) -> Path {
        // A path may be several subpaths; treat each as one polygon and operate pairwise,
        // accumulating. For the common single-polygon case this is just one clip.
        let subjectPolys = a.toPolygons().map(close).filter { $0.count >= 3 }
        let clipPolys = b.toPolygons().map(close).filter { $0.count >= 3 }
        if subjectPolys.isEmpty { return op == .intersection ? Path() : (op == .difference ? Path() : b) }
        if clipPolys.isEmpty { return op == .intersection ? Path() : a }

        // Single-polygon fast path covers the overwhelming majority of uses.
        guard subjectPolys.count == 1, clipPolys.count == 1 else {
            return path(from: subjectPolys + (op == .union ? clipPolys : [])) // conservative fallback
        }
        let result = clipPolygons(subjectPolys[0], clipPolys[0], op: op)
        return path(from: result)
    }

    // MARK: - Greiner-Hormann

    private final class Vertex {
        var point: Point
        var next: Vertex!
        var prev: Vertex!
        var neighbor: Vertex? // the matching intersection in the other polygon
        var isIntersection = false
        var entry = false // true: this intersection enters the other polygon
        var alpha = 0.0 // position along the edge (for sorting inserted intersections)
        var visited = false
        init(_ p: Point) {
            point = p
        }
    }

    /// Clips `subject` against `clip` for the operation. Returns a list of result polygons.
    private static func clipPolygons(_ subject: [Point], _ clip: [Point], op: Operation) -> [[Point]] {
        for jitter in [0.0, 1e-6, 7e-6, 3e-5] { // retry with a tiny nudge if a degeneracy is hit
            let s = jitter == 0 ? subject : subject.map { Point(x: $0.x + jitter, y: $0.y + jitter * 0.5) }
            if let result = clipNonDegenerate(s, clip, op: op) { return result }
        }
        // Could not break the degeneracy; fall back to the no-crossing classification.
        return noCrossingResult(subject, clip, op: op)
    }

    private static func clipNonDegenerate(_ subject: [Point], _ clip: [Point], op: Operation) -> [[Point]]? {
        let subjectList = makeList(subject)
        let clipList = makeList(clip)

        // Phase 1: intersections. Insert crossing points into both rings; bail to the caller
        // (for a jitter retry) if any crossing lands exactly on a vertex (a degeneracy GH cannot
        // mark consistently).
        var crossings = 0
        for sEdge in edges(subjectList) {
            for cEdge in edges(clipList) {
                guard let x = intersect(sEdge.a.point, sEdge.b.point, cEdge.a.point, cEdge.b.point) else { continue }
                if x.degenerate { return nil }
                let sv = Vertex(x.point)
                sv.isIntersection = true
                sv.alpha = x.alphaA
                let cv = Vertex(x.point)
                cv.isIntersection = true
                cv.alpha = x.alphaB
                sv.neighbor = cv
                cv.neighbor = sv
                insert(sv, between: sEdge.a, and: sEdge.b)
                insert(cv, between: cEdge.a, and: cEdge.b)
                crossings += 1
            }
        }
        if crossings == 0 { return noCrossingResult(subject, clip, op: op) }

        // Phase 2: mark entry/exit, then apply the operation's flips.
        markEntryExit(subjectList, otherPolygon: clip)
        markEntryExit(clipList, otherPolygon: subject)
        applyOperation(op, subjectList: subjectList, clipList: clipList)

        // Phase 3: trace result contours.
        return trace(subjectList)
    }

    /// Marks each intersection in `ring` as entry/exit using whether the ring starts inside the
    /// other polygon and toggling at each crossing (intersection semantics).
    private static func markEntryExit(_ ring: Vertex, otherPolygon: [Point]) {
        var inside = pointInPolygon(ring.point, otherPolygon)
        var v: Vertex = ring
        repeat {
            if v.isIntersection {
                v.entry = !inside
                inside.toggle()
            }
            v = v.next
        } while v !== ring
    }

    private static func applyOperation(_ op: Operation, subjectList: Vertex, clipList: Vertex) {
        // With "entry" meaning "enters the other polygon", intersection collects the
        // inside/inside parts (no flip), union collects outside/outside (flip both), and
        // difference (S - C) collects S-outside-C plus C-inside-S, which is the subject ring
        // flipped and the clip ring left as-is.
        switch op {
        case .intersection:
            break
        case .union:
            flipEntry(subjectList)
            flipEntry(clipList)
        case .difference:
            flipEntry(subjectList)
        }
    }

    private static func flipEntry(_ ring: Vertex) {
        var v: Vertex = ring
        repeat {
            if v.isIntersection { v.entry.toggle() }
            v = v.next
        } while v !== ring
    }

    /// Traces result contours: from each unvisited intersection, walk forward while "entry" and
    /// backward otherwise, collecting points until the next intersection, then jump to the
    /// neighbor in the other ring; repeat until the contour closes.
    private static func trace(_ subjectList: Vertex) -> [[Point]] {
        var result: [[Point]] = []
        while let start = firstUnvisited(subjectList) {
            var contour: [Point] = []
            var current = start
            repeat {
                current.visited = true
                if let n = current.neighbor { n.visited = true }
                if current.entry {
                    repeat {
                        current = current.next
                        contour.append(current.point)
                    } while !current.isIntersection
                } else {
                    repeat {
                        current = current.prev
                        contour.append(current.point)
                    } while !current.isIntersection
                }
                current.visited = true
                guard let neighbor = current.neighbor else { break }
                current = neighbor
            } while current !== start && !current.visited
            if contour.count >= 3 {
                result.append(contour)
            }
        }
        return result
    }

    // MARK: - No-crossing classification

    private static func noCrossingResult(_ subject: [Point], _ clip: [Point], op: Operation) -> [[Point]] {
        let sInC = pointInPolygon(subject[0], clip)
        let cInS = pointInPolygon(clip[0], subject)
        switch op {
        case .intersection:
            if sInC { return [subject] }
            if cInS { return [clip] }
            return []
        case .union:
            if sInC { return [clip] }
            if cInS { return [subject] }
            return [subject, clip] // disjoint: both regions
        case .difference:
            if sInC { return [] } // subject entirely removed
            if cInS { return [subject, clip.reversed()] } // clip becomes a hole (reverse winding)
            return [subject] // disjoint: subject unchanged
        }
    }

    // MARK: - Geometry helpers

    private static func close(_ poly: [Point]) -> [Point] {
        guard let first = poly.first, let last = poly.last else { return poly }
        return first == last ? Array(poly.dropLast()) : poly
    }

    private static func makeList(_ points: [Point]) -> Vertex {
        let vertices = points.map(Vertex.init)
        for i in vertices.indices {
            vertices[i].next = vertices[(i + 1) % vertices.count]
            vertices[i].prev = vertices[(i - 1 + vertices.count) % vertices.count]
        }
        return vertices[0]
    }

    private static func edges(_ ring: Vertex) -> [(a: Vertex, b: Vertex)] {
        // Snapshot original (non-intersection) edges before any insertion mutates the ring.
        var out: [(Vertex, Vertex)] = []
        var v: Vertex = ring
        repeat {
            out.append((v, v.next))
            v = v.next
        } while v !== ring
        return out
    }

    /// Inserts `v` into the ring between `a` and `b`, ordered by alpha among any intersections
    /// already sitting on that edge.
    private static func insert(_ v: Vertex, between a: Vertex, and b: Vertex) {
        var c: Vertex = a.next
        while c !== b, c.isIntersection, c.alpha < v.alpha {
            c = c.next
        }
        v.prev = c.prev
        v.next = c
        c.prev.next = v
        c.prev = v
    }

    private static func firstUnvisited(_ ring: Vertex) -> Vertex? {
        var v: Vertex = ring
        repeat {
            if v.isIntersection, !v.visited { return v }
            v = v.next
        } while v !== ring
        return nil
    }

    private struct Crossing { let point: Point
        let alphaA: Double
        let alphaB: Double
        let degenerate: Bool
    }

    /// Segment intersection of a1->a2 and b1->b2. Returns the crossing with edge parameters, or
    /// nil if parallel/non-crossing. `degenerate` is set when a crossing lands on an endpoint.
    private static func intersect(_ a1: Point, _ a2: Point, _ b1: Point, _ b2: Point) -> Crossing? {
        let rx = a2.x - a1.x, ry = a2.y - a1.y
        let sx = b2.x - b1.x, sy = b2.y - b1.y
        let denom = rx * sy - ry * sx
        if abs(denom) < 1e-12 { return nil } // parallel or collinear
        let t = ((b1.x - a1.x) * sy - (b1.y - a1.y) * sx) / denom
        let u = ((b1.x - a1.x) * ry - (b1.y - a1.y) * rx) / denom
        guard t > -1e-9, t < 1 + 1e-9, u > -1e-9, u < 1 + 1e-9 else { return nil }
        let degenerate = t < 1e-7 || t > 1 - 1e-7 || u < 1e-7 || u > 1 - 1e-7
        return Crossing(point: Point(x: a1.x + t * rx, y: a1.y + t * ry), alphaA: t, alphaB: u, degenerate: degenerate)
    }

    private static func pointInPolygon(_ p: Point, _ poly: [Point]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let pi = poly[i], pj = poly[j]
            if (pi.y > p.y) != (pj.y > p.y) {
                let xCross = (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x
                if p.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private static func path(from polygons: [[Point]]) -> Path {
        var path = Path()
        for poly in polygons where poly.count >= 3 {
            path.move(to: poly[0])
            for p in poly.dropFirst() {
                path.addLine(to: p)
            }
            path.closeSubpath()
        }
        return path
    }
}
