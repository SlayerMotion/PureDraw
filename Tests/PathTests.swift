import Testing
import Foundation
@testable import PureDraw

struct PathTests {

    @Test func pathConstruction() {
        var path = PureDraw.Path()
        #expect(path.isEmpty)
        
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 100, y: 10))
        path.addCurve(to: Point(x: 100, y: 100), control1: Point(x: 150, y: 50), control2: Point(x: 150, y: 100))
        path.closeSubpath()
        
        #expect(path.elements.count == 4)
        
        if case .move(let p) = path.elements[0] {
            #expect(p.x == 10 && p.y == 10)
        } else {
            Issue.record("Expected .move")
        }
        
        if case .close = path.elements[3] {
            // Expected
        } else {
            Issue.record("Expected .close")
        }
    }
    
    @Test func pathTransformation() {
        var path = PureDraw.Path()
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 20, y: 20))
        
        let t = PureDraw.AffineTransform.scale(x: 2, y: 3)
        let transformedPath = path.applying(t)
        
        #expect(transformedPath.elements.count == 2)
        
        if case .move(let p) = transformedPath.elements[0] {
            #expect(p.x == 20 && p.y == 30)
        } else {
            Issue.record("Expected .move")
        }
        
        if case .line(let p) = transformedPath.elements[1] {
            #expect(p.x == 40 && p.y == 60)
        } else {
            Issue.record("Expected .line")
        }
    }
}
