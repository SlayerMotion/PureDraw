//
//  TraversalValidationTests.swift
//  PureDraw
//

import Testing
import Foundation
@testable import PureDraw

struct TraversalValidationTests {
    
    @Test func deepPointValidationInPath() {
        var path = Path()
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: .infinity, y: 50)) // Invalid point coordinate
        
        do {
            try path.validate()
            Issue.record("Expected validation to fail due to infinite coordinate")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            let error = errors.values[0]
            #expect(error.reason == "Failed to satisfy: Point coordinates are finite (not NaN or Infinity)")
            // Verify path matches structural traversal
            let pathString = error.description
            #expect(pathString.contains("Failed to satisfy: Point coordinates are finite (not NaN or Infinity) at path: .elements.1.line.to"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test func deepGraphicsContextValidation() {
        var context = GraphicsContext()
        // Set an invalid stroke color component
        context.setStrokeColor(Color(red: 1.5, green: 0.5, blue: 0.5))
        // Set an invalid line width
        context.setLineWidth(-5.0)
        
        do {
            try context.validate()
            Issue.record("Expected validation to fail due to invalid color and line width")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 3) // 1 from Color itself, 2 from GraphicState (color + line width)
            let descriptions = errors.values.map { $0.description }
            
            // Check that it caught the color validation at the exact coding path
            #expect(descriptions.contains { $0.contains(".currentState.strokeColor") })
            #expect(descriptions.contains { $0.contains(".currentState.lineWidth") })
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test func customValidatorCombinedWithDefaultValidators() {
        var path = Path()
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 20, y: 20))
        
        // Custom rule: the path must contain at least 5 elements
        let customValidator = Validator<Path>()
            .validating("Path contains at least 5 elements", check: { (context: ValidationContext<Path, Path>) in
                context.subject.elements.count >= 5
            })
            
        do {
            try path.validate(using: customValidator)
            Issue.record("Expected custom validation to fail")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].reason == "Failed to satisfy: Path contains at least 5 elements")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test func gradientAndShadowValidationRules() throws {
        // 1. Invalid GradientStop
        let badStop = GradientStop(color: .white, location: 1.5)
        do {
            try badStop.validate()
            Issue.record("Expected GradientStop validation to fail")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].reason == "Failed to satisfy: Gradient stop location is between 0.0 and 1.0")
        }
        
        // 2. Invalid Gradient (1 stop)
        let badGrad = Gradient(stops: [GradientStop(color: .white, location: 0.0)])
        do {
            try badGrad.validate()
            Issue.record("Expected Gradient validation to fail")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].reason == "Failed to satisfy: Gradient contains at least two stops")
        }
        
        // 3. Invalid Shadow (negative blur)
        let badShadow = Shadow(offset: Point(x: 0, y: 0), blur: -2.0, color: .black)
        do {
            try badShadow.validate()
            Issue.record("Expected Shadow validation to fail")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].reason == "Failed to satisfy: Shadow blur radius is non-negative")
        }
        
        // 4. Deep traversal context validation
        var context = GraphicsContext()
        context.setShadow(offset: Point(x: 0, y: 0), blur: -5.0, color: .black)
        let stops = [
            GradientStop(color: .white, location: -0.1),
            GradientStop(color: .black, location: 1.0)
        ]
        context.drawLinearGradient(Gradient(stops: stops), start: Point(x: 0, y: 0), end: Point(x: 10, y: 10))
        
        do {
            try context.validate()
            Issue.record("Expected context validation to fail")
        } catch let errors as ValidationErrorCollection {
            let descriptions = errors.values.map { $0.description }
            #expect(descriptions.contains { $0.contains("shadow") && $0.contains("blur") })
            #expect(descriptions.contains { $0.contains("stops") && $0.contains("location") })
        }
    }
}
