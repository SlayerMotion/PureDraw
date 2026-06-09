import Testing
@testable import PureDraw

struct AffineTransformTests {

    @Test func identity() {
        let t = AffineTransform.identity
        #expect(t.a == 1)
        #expect(t.b == 0)
        #expect(t.c == 0)
        #expect(t.d == 1)
        #expect(t.tx == 0)
        #expect(t.ty == 0)
    }

    @Test func translation() {
        let t = AffineTransform.translation(x: 10, y: 20)
        #expect(t.tx == 10)
        #expect(t.ty == 20)
        #expect(t.a == 1 && t.d == 1)
    }

    @Test func concatenation() {
        let t1 = AffineTransform.translation(x: 10, y: 20)
        let t2 = AffineTransform.scale(x: 2, y: 3)
        
        // When t1 (translation) is concatenated with t2 (scale):
        // According to standard matrix math (and CGAffineTransform behavior), 
        // the translation vector is ALSO scaled by t2.
        // t1 * t2: tx = (10 * 2) = 20, ty = (20 * 3) = 60
        let result = t1.concatenating(t2)
        
        #expect(result.a == 2)
        #expect(result.d == 3)
        #expect(result.tx == 20) 
        #expect(result.ty == 60)
    }
    
    @Test func translateBy() {
        let t = AffineTransform.identity.translatedBy(x: 5, y: 15)
        #expect(t.tx == 5)
        #expect(t.ty == 15)
    }
}
