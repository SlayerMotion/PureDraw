import Foundation
@testable import PureDrawCore
import PureGeometry
import PureValidation
import Testing

struct StringKey: CodingKey {
    var stringValue: String
    var intValue: Int? {
        nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }
}

struct GeometryValidationTests {
    @Test func matrixInvertibilityValidation() {
        // Valid matrix
        let validTransform = PureGeometry.AffineTransform.scale(x: 2, y: 2)

        let validResult = Validation<Void, PureGeometry.AffineTransform>.matrixIsReversible.apply(
            to: validTransform,
            at: [StringKey("test"), StringKey("transform")],
            in: (),
        )
        #expect(validResult.isEmpty, "Valid matrix should produce no errors")

        // Singular matrix
        let singularTransform = PureGeometry.AffineTransform.scale(x: 0, y: 0)
        let invalidResult = Validation<Void, PureGeometry.AffineTransform>.matrixIsReversible.apply(
            to: singularTransform,
            at: [StringKey("test"), StringKey("transform")],
            in: (),
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
            in: (),
        )
        #expect(validResult.isEmpty)

        // Invalid rect (negative width)
        let invalidRect = Rect(x: 0, y: 0, width: -10, height: 50)
        let invalidResult = Validation<Void, Rect>.rectHasValidDimensions.apply(
            to: invalidRect,
            at: [StringKey("rect")],
            in: (),
        )
        #expect(invalidResult.count == 1)
        #expect(invalidResult.first?.description == "Failed to satisfy: Rectangle width and height are positive at path: .rect")
    }

    @Test func pointFiniteValidation() {
        let validPoint = Point(x: 0, y: 100)
        let validResult = Validation<Void, Point>.pointIsFinite.apply(
            to: validPoint,
            at: [],
            in: (),
        )
        #expect(validResult.isEmpty)

        let infinitePoint = Point(x: .infinity, y: 0)
        let invalidResult = Validation<Void, Point>.pointIsFinite.apply(
            to: infinitePoint,
            at: [],
            in: (),
        )
        #expect(invalidResult.count == 1)
        #expect(invalidResult.first?.description == "Failed to satisfy: Point coordinates are finite (not NaN or Infinity) at root of document")
    }

    @Test func validatorBuilderAppliesRules() {
        let t = PureGeometry.AffineTransform.scale(x: 0, y: 0)

        // Create a Validator<Void> and add our rule
        let validator = Validator<Void>.blank
            .validating(.matrixIsReversible)

        // The AnyValidation wrapper should automatically match the type and apply the rule
        let errors = validator.apply(to: t, at: [StringKey("myTransform")], in: ())

        #expect(errors.count == 1)
        #expect(errors.first?.description == "Failed to satisfy: Transform matrix determinant is non-zero (matrix is invertible) at path: .myTransform")
    }

    @Test func rectFinitenessValidation() {
        let infiniteRect = Rect(x: 0, y: 0, width: .infinity, height: 10)
        do {
            try infiniteRect.validate()
            Issue.record("Expected Rect validation to fail due to infinite width")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].description.contains("Rectangle dimensions are finite"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let nanRect = Rect(x: 0, y: 0, width: 10, height: .nan)
        do {
            try nanRect.validate()
            Issue.record("Expected Rect validation to fail due to NaN height")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 2) // Fails rectHasValidDimensions (nan >= 0 is false) and rectIsFinite
            let descriptions = errors.values.map(\.description)
            #expect(descriptions.contains { $0.contains("Rectangle width and height are positive") })
            #expect(descriptions.contains { $0.contains("Rectangle dimensions are finite") })
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func matrixFinitenessValidation() {
        let infiniteMatrix = PureGeometry.AffineTransform(a: 1, b: .infinity, c: 0, d: 1, tx: 0, ty: 0)
        do {
            try infiniteMatrix.validate()
            Issue.record("Expected AffineTransform validation to fail due to infinite component")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].description.contains("Transform matrix components are finite"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func pathStructureIntegrityValidation() {
        // Path that starts with addLine instead of move
        var invalidPath = Path()
        invalidPath.addLine(to: Point(x: 10, y: 10))
        do {
            try invalidPath.validate()
            Issue.record("Expected path validation to fail because it doesn't start with move")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 2) // One for starts with move, one for Line operation before move
            let reasons = errors.values.map(\.reason)
            #expect(reasons.contains("Path must start with a move operation"))
            #expect(reasons.contains("Line operation at index 0 occurs before any move operation"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        // Path with singular quadratic curve
        var singularPath = Path()
        singularPath.move(to: Point(x: 10, y: 10))
        singularPath.addQuadCurve(to: Point(x: 10, y: 10), control: Point(x: 10, y: 10))
        do {
            try singularPath.validate()
            Issue.record("Expected path validation to fail because quadratic curve is singular")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].reason.contains("Quadratic curve at index 1 is singular"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        // Path with singular cubic curve
        var singularCubicPath = Path()
        singularCubicPath.move(to: Point(x: 5, y: 5))
        singularCubicPath.addCurve(to: Point(x: 5, y: 5), control1: Point(x: 5, y: 5), control2: Point(x: 5, y: 5))
        do {
            try singularCubicPath.validate()
            Issue.record("Expected path validation to fail because cubic curve is singular")
        } catch let errors as ValidationErrorCollection {
            #expect(errors.values.count == 1)
            #expect(errors.values[0].reason.contains("Cubic curve at index 1 is singular"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
