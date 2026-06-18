@testable import Geometry
import Testing

/// Property-based adversarial fuzzing of the geometry primitives: invariants that must hold
/// for ANY (including degenerate / non-finite) input. Transform invertibility round-trips
/// (used by transform3D), rectangle set algebra (used by clipping), and the no-trap contract
/// on non-finite values. Seeded for reproducibility.
struct GeometryPropertyFuzzTests {
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func d(_ rng: inout SplitMix64, _ range: ClosedRange<Double> = -20 ... 20) -> Double {
        Double.random(in: range, using: &rng)
    }

    @Test func affineInvertibleRoundTrip() {
        for seed in UInt64(1) ... 300 {
            var rng = SplitMix64(state: seed &* 0x100_0000_01B3 &+ 1)
            let t = AffineTransform(a: d(&rng), b: d(&rng), c: d(&rng), d: d(&rng), tx: d(&rng), ty: d(&rng))
            guard abs(t.determinant) > 0.05 else { continue } // only invertible transforms
            let inv = t.inverted()
            let p = Point(x: d(&rng), y: d(&rng))
            let round = p.applying(t).applying(inv)
            #expect(abs(round.x - p.x) < 1e-4 && abs(round.y - p.y) < 1e-4, "affine seed \(seed): round-trip \(round) != \(p)")
        }
    }

    @Test func projectiveInvertibleRoundTrip() {
        for seed in UInt64(1) ... 300 {
            var rng = SplitMix64(state: seed &* 0x1000_0193 &+ 7)
            // Build a projective transform from a non-degenerate rect->quad mapping.
            let rect = Rect(x: 0, y: 0, width: d(&rng, 4 ... 40), height: d(&rng, 4 ... 40))
            let t = ProjectiveTransform.rectToQuad(
                rect,
                p0: Point(x: d(&rng, 0 ... 10), y: d(&rng, 0 ... 10)),
                p1: Point(x: d(&rng, 30 ... 50), y: d(&rng, 0 ... 10)),
                p2: Point(x: d(&rng, 30 ... 50), y: d(&rng, 30 ... 50)),
                p3: Point(x: d(&rng, 0 ... 10), y: d(&rng, 30 ... 50))
            )
            guard abs(t.determinant) > 0.001 else { continue }
            let inv = t.inverted()
            let p = Point(x: d(&rng, 1 ... 39), y: d(&rng, 1 ... 39))
            let round = p.applying(t).applying(inv)
            #expect(abs(round.x - p.x) < 1e-2 && abs(round.y - p.y) < 1e-2, "projective seed \(seed): round-trip \(round) != \(p)")
        }
    }

    @Test func rectSetAlgebraInvariants() {
        func rect(_ rng: inout SplitMix64) -> Rect {
            Rect(x: d(&rng), y: d(&rng), width: d(&rng, 0 ... 30), height: d(&rng, 0 ... 30))
        }
        for seed in UInt64(1) ... 400 {
            var rng = SplitMix64(state: seed &* 0x9E37 &+ 3)
            let a = rect(&rng), b = rect(&rng)
            // Intersection is commutative.
            let ab = a.intersection(b), ba = b.intersection(a)
            #expect(ab.isNull == ba.isNull, "intersection commutativity (null) seed \(seed)")
            if !ab.isNull, !ba.isNull {
                #expect(abs(ab.minX - ba.minX) < 1e-9 && abs(ab.width - ba.width) < 1e-9, "intersection not commutative seed \(seed)")
            }
            // A non-null intersection is contained in both operands.
            if !ab.isNull, !ab.isEmpty {
                #expect(a.contains(ab) && b.contains(ab), "intersection \(ab) not within both operands seed \(seed)")
            }
            // Union covers both operands when neither is EMPTY. (CoreGraphics semantics:
            // union ignores an empty rect and returns the other, verified separately.) Test
            // the bounds with an epsilon rather than the exact contains(): union stores
            // width = maxX - minX, so u.maxX = minX + (maxX - minX) carries ~1e-14 of
            // rounding, which an exact containment check would spuriously reject.
            if !a.isEmpty, !b.isEmpty {
                let u = a.union(b)
                let eps = 1e-9
                #expect(
                    u.minX <= min(a.minX, b.minX) + eps && u.maxX >= max(a.maxX, b.maxX) - eps
                        && u.minY <= min(a.minY, b.minY) + eps && u.maxY >= max(a.maxY, b.maxY) - eps,
                    "union \(u) does not cover both operands seed \(seed)"
                )
            }
        }
    }

    @Test func disjointRectsIntersectToNothing() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 40, y: 40, width: 10, height: 10) // fully disjoint
        let i = a.intersection(b)
        #expect(i.isNull || i.isEmpty, "disjoint rects must intersect to null/empty, got \(i)")
    }

    @Test func unionIgnoresEmptyOperand() {
        // CoreGraphics semantics: union with an empty (zero width/height) rect returns the
        // other operand unchanged; the empty rect's position does not extend the result.
        let a = Rect(x: 5, y: 5, width: 10, height: 10)
        let empty = Rect(x: 100, y: 100, width: 0, height: 8)
        let viaA = a.union(empty), viaEmpty = empty.union(a)
        #expect(viaA.minX == a.minX && viaA.width == a.width && viaA.height == a.height, "union with empty must return the other")
        #expect(viaEmpty.minX == a.minX && viaEmpty.width == a.width, "union with empty is commutative")
    }

    @Test func nonFiniteGeometryDoesNotTrap() {
        // NaN/Inf coordinates must not trap the geometry ops (they may yield NaN, not crash).
        let bad = [Double.nan, .infinity, -.infinity]
        for v in bad {
            let t = AffineTransform(a: v, b: 0, c: 0, d: 1, tx: v, ty: 0)
            _ = Point(x: v, y: 0).applying(t)
            _ = t.determinant
            if abs(t.determinant) > 0 { _ = t.inverted() }
            let r1 = Rect(x: v, y: 0, width: 10, height: v)
            let r2 = Rect(x: 0, y: 0, width: 10, height: 10)
            _ = r1.intersection(r2)
            _ = r1.union(r2)
            _ = r1.contains(Point(x: v, y: v))
            _ = r1.insetBy(dx: v, dy: 1)
        } // must not trap
    }
}
