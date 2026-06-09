import Testing
import Foundation
@testable import PureDraw

struct AffineTransformTests {

    // Helper to check floating point equality within a tolerance
    private func isAlmostEqual(_ a: Double, _ b: Double, tolerance: Double = 0.000001) -> Bool {
        return abs(a - b) < tolerance
    }

    private func isAlmostEqual(_ t1: PureDraw.AffineTransform, _ t2: PureDraw.AffineTransform) -> Bool {
        return isAlmostEqual(t1.a, t2.a) &&
               isAlmostEqual(t1.b, t2.b) &&
               isAlmostEqual(t1.c, t2.c) &&
               isAlmostEqual(t1.d, t2.d) &&
               isAlmostEqual(t1.tx, t2.tx) &&
               isAlmostEqual(t1.ty, t2.ty)
    }

    @Test func identity() {
        let t = PureDraw.AffineTransform.identity
        #expect(t.a == 1)
        #expect(t.b == 0)
        #expect(t.c == 0)
        #expect(t.d == 1)
        #expect(t.tx == 0)
        #expect(t.ty == 0)
    }

    @Test func algebraicInvertibility() {
        let t = PureDraw.AffineTransform.identity
            .translatedBy(x: 100, y: -50)
            .scaledBy(x: 2.0, y: 0.5)
            .rotated(by: Double.pi / 4) // 45 degrees
            
        let inverted = t.inverted()
        let result = t.concatenating(inverted)
        
        // A matrix multiplied by its inverse MUST yield the Identity matrix.
        #expect(isAlmostEqual(result, PureDraw.AffineTransform.identity))
    }
    
    @Test func algebraicAssociativity() {
        let t1 = PureDraw.AffineTransform.translation(x: 10, y: 20)
        let t2 = PureDraw.AffineTransform.scale(x: 2, y: 3)
        let t3 = PureDraw.AffineTransform.rotation(angle: Double.pi / 6)
        
        // (A * B) * C == A * (B * C)
        let leftGroup = t1.concatenating(t2).concatenating(t3)
        let rightGroup = t1.concatenating(t2.concatenating(t3))
        
        #expect(isAlmostEqual(leftGroup, rightGroup))
    }
    
    @Test func singularMatrixInversion() {
        // A matrix with scale 0 has a determinant of 0.
        let singular = PureDraw.AffineTransform.scale(x: 0, y: 0)
        #expect(singular.determinant == 0)
        
        // It should gracefully return itself rather than crashing with division-by-zero.
        let result = singular.inverted()
        #expect(result == singular)
    }
    
    @Test func pointApplication() {
        let p = Point(x: 10, y: 10)
        
        // Test basic scale
        let t1 = PureDraw.AffineTransform.scale(x: 2, y: 3)
        let r1 = p.applying(t1)
        #expect(r1.x == 20 && r1.y == 30)
        
        // Test basic translation
        let t2 = PureDraw.AffineTransform.translation(x: 5, y: -5)
        let r2 = p.applying(t2)
        #expect(r2.x == 15 && r2.y == 5)
        
        // Test sequence: Scale then Translate
        // According to our concatenation logic: t1.concatenating(t2)
        // (x * 2) + 5 = 25
        // (y * 3) - 5 = 25
        let t3 = t1.concatenating(t2)
        let r3 = p.applying(t3)
        #expect(r3.x == 25 && r3.y == 25)
    }
}
