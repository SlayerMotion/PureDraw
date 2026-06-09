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
}
