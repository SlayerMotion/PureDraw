//
//  ValidationConfigurationTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing
import Validation

/// The configuration pin (the canon's "configuration-pin test"): every default
/// validator's exact ordered rule list is asserted, so adding, removing, or
/// rewording a rule fails a test before the change is deliberate.
struct ValidationConfigurationTests {
    @Test func blankValidatorIsEmpty() {
        #expect(Validator<Color>.blank.validationDescriptions.isEmpty)
    }

    @Test func colorPinsItsRule() {
        #expect(Color.defaultValidator.validationDescriptions == [
            "Color components are within 0.0 and 1.0",
        ])
    }

    @Test func pointPinsItsRule() {
        #expect(Point.defaultValidator.validationDescriptions == [
            "Point coordinates are finite (not NaN or Infinity)",
        ])
    }

    @Test func rectPinsItsRules() {
        #expect(Rect.defaultValidator.validationDescriptions == [
            "Rectangle width and height are non-negative",
            "Rectangle dimensions are finite",
        ])
    }

    @Test func affineTransformPinsItsRules() {
        #expect(AffineTransform.defaultValidator.validationDescriptions == [
            "Transform matrix determinant is non-zero (matrix is invertible)",
            "Transform matrix components are finite",
        ])
    }

    @Test func projectiveTransformPinsItsRules() {
        #expect(ProjectiveTransform.defaultValidator.validationDescriptions == [
            "Projective transform matrix determinant is non-zero (matrix is invertible)",
            "Projective transform matrix components are finite",
        ])
    }

    @Test func gradientPinsItsRule() {
        #expect(Gradient.defaultValidator.validationDescriptions == [
            "Gradient contains at least two stops",
        ])
    }

    @Test func gradientStopPinsItsRule() {
        #expect(GradientStop.defaultValidator.validationDescriptions == [
            "Gradient stop location is between 0.0 and 1.0",
        ])
    }

    @Test func shadowPinsItsRule() {
        #expect(Shadow.defaultValidator.validationDescriptions == [
            "Shadow blur radius is non-negative",
        ])
    }

    @Test func imagePinsItsRule() {
        #expect(Image.defaultValidator.validationDescriptions == [
            "Image dimensions and data are valid",
        ])
    }

    @Test func pathPinsItsRule() {
        #expect(Path.defaultValidator.validationDescriptions == [
            "Path has valid structure and geometry",
        ])
    }

    @Test func crumpleDeformerPinsItsRule() {
        #expect(CrumpleDeformer.defaultValidator.validationDescriptions == [
            "CrumpleDeformer center, radius, and strengths are finite",
        ])
    }

    @Test func graphicStatePinsItsRule() {
        #expect(GraphicState.defaultValidator.validationDescriptions == [
            "Graphic state properties are valid",
        ])
    }

    @Test func graphicsContextPinsItsRule() {
        #expect(GraphicsContext.defaultValidator.validationDescriptions == [
            "Transparency layers are balanced",
        ])
    }

    @Test func drawOperationPinsItsRules() {
        #expect(DrawOperation.defaultValidator.validationDescriptions == [
            "Draw operation path is not empty",
            "Linear gradient start and end points are distinct",
            "Radial gradient configuration is valid",
            "Projective image transform is invertible and finite",
            "Layer stamp has positive dimensions",
            "Text-show operation parameters are valid",
        ])
    }
}
