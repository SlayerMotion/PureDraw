import Foundation
@testable import Geometry
import Testing

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Proves the affine decomposition is the exact inverse of recomposition, and that our affine
/// primitives agree with Apple's `CGAffineTransform` on the same inputs. The editor's decomposition
/// panel and Swift projection rest on this.
@Suite("Affine decomposition")
struct AffineDecompositionTests {
    private typealias AT = Geometry.AffineTransform

    private func approx(_ x: Double, _ y: Double, _ tol: Double = 1e-9) -> Bool { abs(x - y) <= tol }

    private func same(_ lhs: AT, _ rhs: AT, _ tol: Double = 1e-9) -> Bool {
        approx(lhs.a, rhs.a, tol) && approx(lhs.b, rhs.b, tol) && approx(lhs.c, rhs.c, tol)
            && approx(lhs.d, rhs.d, tol) && approx(lhs.tx, rhs.tx, tol) && approx(lhs.ty, rhs.ty, tol)
    }

    private let samples: [AT] = [
        .identity,
        .rotation(angle: .pi / 6),
        .scale(x: 2, y: 3),
        .skew(x: 0.45, y: 0),
        .translation(x: 10, y: -20),
        AT(a: 1.134, b: 0.325, c: -0.076, d: 0.873, tx: 0, ty: 0), // card tilt
        AT(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0), // a horizontal flip
        AT(a: 0.6, b: 0.4, c: -0.2, d: 1.1, tx: 7, ty: -3), // a general matrix
    ]

    @Test func recomposeOfDecomposeReproducesTheMatrix() {
        for matrix in samples {
            let roundTrip = AT.recomposed(matrix.decomposed())
            #expect(same(matrix, roundTrip), "round-trip failed for \(matrix)")
        }
    }

    @Test func decomposeReadsTheObviousMotions() {
        let scale = AT.scale(x: 2, y: 3).decomposed()
        #expect(approx(scale.scaleX, 2) && approx(scale.scaleY, 3))
        #expect(approx(scale.rotation, 0) && approx(scale.skew, 0))

        let rotation = AT.rotation(angle: .pi / 6).decomposed()
        #expect(approx(rotation.rotation, .pi / 6))
        #expect(approx(rotation.scaleX, 1) && approx(rotation.scaleY, 1) && approx(rotation.skew, 0))

        let translation = AT.translation(x: 12, y: -8).decomposed()
        #expect(approx(translation.translationX, 12) && approx(translation.translationY, -8))
    }

    @Test func recomposeOfDecomposeReproducesAGridOfMatrices() {
        // A deterministic grid of linear parts with a fixed translation. Near-singular matrices are
        // skipped (the QR factorisation is ill-conditioned there); every well-conditioned one must
        // round-trip, proving the decomposition is the exact inverse well beyond the curated samples.
        let values = [-1.3, -0.7, 0.0, 0.5, 1.1, 2.0]
        var checked = 0
        for a in values {
            for b in values {
                for c in values {
                    for d in values where abs((a * d) - (b * c)) > 0.05 {
                        let matrix = AT(a: a, b: b, c: c, d: d, tx: 3, ty: -5)
                        #expect(same(matrix, AT.recomposed(matrix.decomposed())), "round-trip failed for \(matrix)")
                        checked += 1
                    }
                }
            }
        }
        #expect(checked > 1000)
    }

    #if canImport(CoreGraphics)
        @Test func primitivesMatchCoreGraphics() {
            let angle = 0.7
            #expect(same(.rotation(angle: angle), from(CGAffineTransform(rotationAngle: angle))))
            #expect(same(.scale(x: 1.5, y: 0.8), from(CGAffineTransform(scaleX: 1.5, y: 0.8))))
            #expect(same(.translation(x: 9, y: -4), from(CGAffineTransform(translationX: 9, y: -4))))

            // Concatenation order matches CGAffineTransformConcat (self followed by t2 == self * t2).
            let a = AT(a: 0.6, b: 0.4, c: -0.2, d: 1.1, tx: 7, ty: -3)
            let b = AT.rotation(angle: 0.3)
            #expect(same(a.concatenating(b), from(cg(a).concatenating(cg(b)))))

            // Inversion matches CGAffineTransformInvert.
            #expect(same(a.inverted(), from(cg(a).inverted())))
        }

        private func from(_ t: CGAffineTransform) -> AT {
            AT(a: Double(t.a), b: Double(t.b), c: Double(t.c), d: Double(t.d), tx: Double(t.tx), ty: Double(t.ty))
        }

        private func cg(_ t: AT) -> CGAffineTransform {
            CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty)
        }
    #endif
}
