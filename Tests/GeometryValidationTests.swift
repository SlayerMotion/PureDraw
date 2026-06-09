import Testing
import Foundation
@testable import PureDraw

struct StringKey: CodingKey {
    var stringValue: String
    var intValue: Int? { return nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
}

struct GeometryValidationTests {
    
    @Test func matrixInvertibilityValidation() {
        // Valid matrix
        let validTransform = PureDraw.AffineTransform.scale(x: 2, y: 2)
        
        let validResult = Validation<Void, PureDraw.AffineTransform>.matrixIsReversible.apply(
            to: validTransform, 
            at: [StringKey("test"), StringKey("transform")], 
            in: ()
        )
        #expect(validResult.isEmpty, "Valid matrix should produce no errors")
        
        // Singular matrix
        let singularTransform = PureDraw.AffineTransform.scale(x: 0, y: 0)
        let invalidResult = Validation<Void, PureDraw.AffineTransform>.matrixIsReversible.apply(
            to: singularTransform, 
            at: [StringKey("test"), StringKey("transform")], 
            in: ()
        )
        
        #expect(invalidResult.count == 1)
        #expect(invalidResult.first?.reason == "Failed to satisfy: Transform matrix determinant is non-zero (matrix is invertible)")
        #expect(invalidResult.first?.description == "Failed to satisfy: Transform matrix determinant is non-zero (matrix is invertible) at path: .test.transform")
    }
    
    @Test func rectDimensionsValidation() {
        // Valid rect
        let validRect = Rect(x: 10, y: 10, width: 100, height: 50)
        let validResult = Validation<Void, Rect>.rectHasValidDimensions.apply(
            to: validRect, 
            at: [StringKey("rect")], 
            in: ()
        )
        #expect(validResult.isEmpty)
        
        // Invalid rect (negative width)
        let invalidRect = Rect(x: 0, y: 0, width: -10, height: 50)
        let invalidResult = Validation<Void, Rect>.rectHasValidDimensions.apply(
            to: invalidRect, 
            at: [StringKey("rect")], 
            in: ()
        )
        #expect(invalidResult.count == 1)
        #expect(invalidResult.first?.description == "Failed to satisfy: Rectangle width and height are positive at path: .rect")
    }
    
    @Test func pointFiniteValidation() {
        let validPoint = Point(x: 0, y: 100)
        let validResult = Validation<Void, Point>.pointIsFinite.apply(
            to: validPoint, 
            at: [], 
            in: ()
        )
        #expect(validResult.isEmpty)
        
        let infinitePoint = Point(x: .infinity, y: 0)
        let invalidResult = Validation<Void, Point>.pointIsFinite.apply(
            to: infinitePoint, 
            at: [], 
            in: ()
        )
        #expect(invalidResult.count == 1)
        #expect(invalidResult.first?.description == "Failed to satisfy: Point coordinates are finite (not NaN or Infinity) at root of document")
    }
    
    @Test func validatorBuilderAppliesRules() {
        let t = PureDraw.AffineTransform.scale(x: 0, y: 0)
        
        // Create a Validator<Void> and add our rule
        let validator = Validator<Void>.blank
            .validating(.matrixIsReversible)
        
        // The AnyValidation wrapper should automatically match the type and apply the rule
        let errors = validator.apply(to: t, at: [StringKey("myTransform")], in: ())
        
        #expect(errors.count == 1)
        #expect(errors.first?.description == "Failed to satisfy: Transform matrix determinant is non-zero (matrix is invertible) at path: .myTransform")
    }
}
