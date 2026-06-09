import Testing
import Foundation
@testable import PureDraw

struct ProjectiveTransformTests {

    private func isAlmostEqual(_ a: Double, _ b: Double, tolerance: Double = 0.000001) -> Bool {
        return abs(a - b) < tolerance
    }

    private func isAlmostEqual(_ p1: Point, _ p2: Point, tolerance: Double = 0.000001) -> Bool {
        return isAlmostEqual(p1.x, p2.x, tolerance: tolerance) && isAlmostEqual(p1.y, p2.y, tolerance: tolerance)
    }

    private func isAlmostEqual(_ t1: ProjectiveTransform, _ t2: ProjectiveTransform, tolerance: Double = 0.000001) -> Bool {
        return isAlmostEqual(t1.m11, t2.m11, tolerance: tolerance) &&
               isAlmostEqual(t1.m12, t2.m12, tolerance: tolerance) &&
               isAlmostEqual(t1.m13, t2.m13, tolerance: tolerance) &&
               isAlmostEqual(t1.m21, t2.m21, tolerance: tolerance) &&
               isAlmostEqual(t1.m22, t2.m22, tolerance: tolerance) &&
               isAlmostEqual(t1.m23, t2.m23, tolerance: tolerance) &&
               isAlmostEqual(t1.m31, t2.m31, tolerance: tolerance) &&
               isAlmostEqual(t1.m32, t2.m32, tolerance: tolerance) &&
               isAlmostEqual(t1.m33, t2.m33, tolerance: tolerance)
    }

    @Test func identity() {
        let t = ProjectiveTransform.identity
        let p = Point(x: 5.0, y: 10.0)
        let result = p.applying(t)
        #expect(isAlmostEqual(result, p))
    }

    @Test func affineConversion() {
        let affine = AffineTransform.identity
            .translatedBy(x: 20, y: -30)
            .scaledBy(x: 2.5, y: 1.5)
            .skewedBy(x: 0.2, y: 0.1)
        
        let proj = ProjectiveTransform(affine)
        let p = Point(x: 10, y: 10)
        
        let pAffine = p.applying(affine)
        let pProj = p.applying(proj)
        
        #expect(isAlmostEqual(pAffine, pProj))
    }

    @Test func algebraicAssociativity() {
        let t1 = ProjectiveTransform(AffineTransform.translation(x: 10, y: 20))
        
        // Non-affine perspective matrix
        let t2 = ProjectiveTransform(
            m11: 1.0, m12: 0.2, m13: 0.005,
            m21: 0.1, m22: 1.2, m23: 0.002,
            m31: 5.0, m32: 2.0, m33: 1.0
        )
        
        let t3 = ProjectiveTransform(AffineTransform.scale(x: 2.0, y: 3.0))
        
        let leftGroup = t1.concatenated(with: t2).concatenated(with: t3)
        let rightGroup = t1.concatenated(with: t2.concatenated(with: t3))
        
        #expect(isAlmostEqual(leftGroup, rightGroup))
    }

    @Test func unitSquareMapping() {
        // Define target quad corners corresponding to (0,0), (1,0), (1,1), (0,1)
        let p0 = Point(x: 10.0, y: 10.0)
        let p1 = Point(x: 100.0, y: 20.0)
        let p2 = Point(x: 90.0, y: 80.0)
        let p3 = Point(x: 20.0, y: 90.0)
        
        let t = ProjectiveTransform.unitSquareToQuad(p0: p0, p1: p1, p2: p2, p3: p3)
        
        #expect(isAlmostEqual(Point(x: 0, y: 0).applying(t), p0))
        #expect(isAlmostEqual(Point(x: 1, y: 0).applying(t), p1))
        #expect(isAlmostEqual(Point(x: 1, y: 1).applying(t), p2))
        #expect(isAlmostEqual(Point(x: 0, y: 1).applying(t), p3))
    }

    @Test func rectMapping() {
        let rect = Rect(x: 50.0, y: 50.0, width: 100.0, height: 100.0)
        
        let p0 = Point(x: 200.0, y: 100.0)
        let p1 = Point(x: 400.0, y: 120.0)
        let p2 = Point(x: 350.0, y: 300.0)
        let p3 = Point(x: 220.0, y: 280.0)
        
        let t = ProjectiveTransform.rectToQuad(rect, p0: p0, p1: p1, p2: p2, p3: p3)
        
        #expect(isAlmostEqual(Point(x: 50, y: 50).applying(t), p0))
        #expect(isAlmostEqual(Point(x: 150, y: 50).applying(t), p1))
        #expect(isAlmostEqual(Point(x: 150, y: 150).applying(t), p2))
        #expect(isAlmostEqual(Point(x: 50, y: 150).applying(t), p3))
    }

    @Test func algebraicInvertibility() {
        let t = ProjectiveTransform(
            m11: 1.0, m12: 0.2, m13: 0.005,
            m21: 0.1, m22: 1.2, m23: 0.002,
            m31: 5.0, m32: 2.0, m33: 1.0
        )
        
        let inv = t.inverted()
        let identity1 = t.concatenated(with: inv)
        let identity2 = inv.concatenated(with: t)
        
        // In order to check if identity, we normalize the product so that m33 is 1.0
        let norm1 = ProjectiveTransform(
            m11: identity1.m11 / identity1.m33, m12: identity1.m12 / identity1.m33, m13: identity1.m13 / identity1.m33,
            m21: identity1.m21 / identity1.m33, m22: identity1.m22 / identity1.m33, m23: identity1.m23 / identity1.m33,
            m31: identity1.m31 / identity1.m33, m32: identity1.m32 / identity1.m33, m33: 1.0
        )
        
        let norm2 = ProjectiveTransform(
            m11: identity2.m11 / identity2.m33, m12: identity2.m12 / identity2.m33, m13: identity2.m13 / identity2.m33,
            m21: identity2.m21 / identity2.m33, m22: identity2.m22 / identity2.m33, m23: identity2.m23 / identity2.m33,
            m31: identity2.m31 / identity2.m33, m32: identity2.m32 / identity2.m33, m33: 1.0
        )
        
        #expect(isAlmostEqual(norm1, ProjectiveTransform.identity))
        #expect(isAlmostEqual(norm2, ProjectiveTransform.identity))
    }

    @Test func singularMatrixInversion() {
        // Zero scale matrix
        let singular = ProjectiveTransform(
            m11: 0, m12: 0, m13: 0,
            m21: 0, m22: 0, m23: 0,
            m31: 0, m32: 0, m33: 0
        )
        #expect(singular.determinant == 0.0)
        
        let inv = singular.inverted()
        #expect(inv == singular)
    }

    @Test func validationRules() {
        let valid = ProjectiveTransform.identity
        #expect(throws: Never.self) {
            try valid.validate()
        }
        
        // Fails finite check
        let invalid1 = ProjectiveTransform(
            m11: .infinity, m12: 0, m13: 0,
            m21: 0, m22: 1, m23: 0,
            m31: 0, m32: 0, m33: 1
        )
        
        do {
            try invalid1.validate()
            Issue.record("Expected validation to fail due to infinite component")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].reason.contains("Projective transform matrix components are finite"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        
        // Fails invertibility check
        let invalid2 = ProjectiveTransform(
            m11: 0, m12: 0, m13: 0,
            m21: 0, m22: 0, m23: 0,
            m31: 0, m32: 0, m33: 1
        )
        do {
            try invalid2.validate()
            Issue.record("Expected validation to fail due to singular matrix")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].reason.contains("Projective transform matrix determinant is non-zero"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
