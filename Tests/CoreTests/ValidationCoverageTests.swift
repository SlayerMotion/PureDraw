//
//  ValidationCoverageTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing
import Validation

/// The coverage law (the canon's "coverage is itself a tested law"): a frozen
/// registry of every finding the default validators can produce. The meta-test
/// asserts the union of all default-validator descriptions equals the registry, so a
/// rule added to ANY validator fails here until it is registered (and, by
/// convention, given its failing + near-miss boundary pair in
/// `ValidationBoundaryTests`).
struct ValidationCoverageTests {
    /// Every default validator in the package. Add a type here when it gains one.
    private var allDefaultDescriptions: Set<String> {
        let lists: [[String]] = [
            Color.defaultValidator.validationDescriptions,
            Point.defaultValidator.validationDescriptions,
            Rect.defaultValidator.validationDescriptions,
            AffineTransform.defaultValidator.validationDescriptions,
            ProjectiveTransform.defaultValidator.validationDescriptions,
            Gradient.defaultValidator.validationDescriptions,
            GradientStop.defaultValidator.validationDescriptions,
            Shadow.defaultValidator.validationDescriptions,
            Image.defaultValidator.validationDescriptions,
            Path.defaultValidator.validationDescriptions,
            GraphicState.defaultValidator.validationDescriptions,
            GraphicsContext.defaultValidator.validationDescriptions,
            DrawOperation.defaultValidator.validationDescriptions,
            CrumpleDeformer.defaultValidator.validationDescriptions,
        ]
        return Set(lists.flatMap { $0 })
    }

    /// The registered findings, each of which has a failing + near-miss fixture in
    /// the boundary/completeness suites.
    private let registry: Set<String> = [
        "Color components are within 0.0 and 1.0",
        "Point coordinates are finite (not NaN or Infinity)",
        "Rectangle width and height are non-negative",
        "Rectangle dimensions are finite",
        "Transform matrix determinant is non-zero (matrix is invertible)",
        "Transform matrix components are finite",
        "Projective transform matrix determinant is non-zero (matrix is invertible)",
        "Projective transform matrix components are finite",
        "Gradient contains at least two stops",
        "Gradient stop location is between 0.0 and 1.0",
        "Shadow blur radius is non-negative",
        "Image dimensions and data are valid",
        "Path has valid structure and geometry",
        "Graphic state properties are valid",
        "Transparency layers are balanced",
        "Draw operation path is not empty",
        "Linear gradient start and end points are distinct",
        "Radial gradient configuration is valid",
        "Projective image transform is invertible and finite",
        "Layer stamp has positive dimensions",
        "Text-show operation parameters are valid",
        "CrumpleDeformer center, radius, and strengths are finite",
    ]

    @Test func everyDefaultFindingIsRegistered() {
        let found = allDefaultDescriptions
        #expect(found == registry, "unregistered findings: \(found.subtracting(registry)); stale registry entries: \(registry.subtracting(found))")
    }
}
